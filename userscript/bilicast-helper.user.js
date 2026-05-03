// ==UserScript==
// @name         BiliCast
// @namespace    https://github.com/jianzhoujz/bilicast
// @version      0.4.2
// @description  在 B 站网页视频页注入"投屏"按钮，调用 Mac 本地服务把视频投到 DLNA 设备。三档清晰度（MP4/FLV/DASH-remux）。
// @author       BiliCast
// @match        https://www.bilibili.com/video/*
// @match        https://www.bilibili.com/list/*
// @match        https://www.bilibili.com/bangumi/play/*
// @run-at       document-idle
// @connect      127.0.0.1
// @connect      localhost
// @connect      api.bilibili.com
// @grant        GM_xmlhttpRequest
// @grant        GM_addStyle
// @grant        GM_registerMenuCommand
// @grant        GM_getValue
// @grant        GM_setValue
// ==/UserScript==

(function () {
  'use strict';

  const LOCAL_API = 'http://127.0.0.1:18787';
  const TOKEN_KEY = 'bilicast.token';
  const BUTTON_ID = 'bilicast-cast-btn';
  const HOST_ID = 'bilicast-host';
  const TOAST_TIMEOUT_MS = 4000;

  // TV-signed playurl appkey/secret (TV box). Public knowledge but rotates occasionally.
  // Keeping these here — userscript runs in user's browser, no secret to protect.
  const TV_APPKEY = '4409e2ce8ffd12b8';
  const TV_APPSEC = '59b43e04ad6965f34319062b478f83dd';

  // --- helpers ---------------------------------------------------------------

  function isBilibiliVideoPage() {
    return /^\/video\/(BV|av)/i.test(location.pathname) ||
           /^\/list\//i.test(location.pathname);
  }
  function isBangumiPage() {
    return /^\/bangumi\/play\//i.test(location.pathname);
  }
  function extractBvFromUrl(url = location.href) {
    const m = url.match(/\/video\/(BV[0-9A-Za-z]+)/);
    return m ? m[1] : null;
  }
  function getVideoTitle() {
    const h1 = document.querySelector('h1.video-title, h1[title]');
    if (h1) return (h1.getAttribute('title') || h1.textContent || '').trim();
    return document.title.replace(/_哔哩哔哩.*$/, '').trim();
  }
  function getCurrentTime() {
    const v = document.querySelector('video');
    return v && Number.isFinite(v.currentTime) ? v.currentTime : 0;
  }
  let cachedToken = '';

  function getExtensionRuntime() {
    try {
      if (typeof chrome !== 'undefined' && chrome.runtime && chrome.runtime.id) return chrome.runtime;
      if (typeof browser !== 'undefined' && browser.runtime && browser.runtime.id) return browser.runtime;
    } catch (_) {}
    return null;
  }

  function sendExtensionMessage(message) {
    const runtime = getExtensionRuntime();
    if (!runtime || typeof runtime.sendMessage !== 'function') return Promise.resolve(null);
    return new Promise((resolve) => {
      let settled = false;
      const done = (value) => {
        if (settled) return;
        settled = true;
        resolve(value || null);
      };
      try {
        const maybePromise = runtime.sendMessage(message, (response) => {
          let lastError = null;
          try { lastError = runtime.lastError; } catch (_) {}
          done(lastError ? null : response);
        });
        if (maybePromise && typeof maybePromise.then === 'function') {
          maybePromise.then(done, () => done(null));
        }
      } catch (_) {
        done(null);
      }
    });
  }

  async function getLocalToken() {
    try {
      if (typeof GM_getValue === 'function') {
        cachedToken = GM_getValue(TOKEN_KEY, '') || '';
        return cachedToken;
      }
    } catch (_) {}
    const response = await sendExtensionMessage({ type: 'bilicast.storage.get', key: TOKEN_KEY });
    if (response && response.ok) cachedToken = response.value || '';
    return cachedToken;
  }

  async function setLocalToken(token) {
    cachedToken = token || '';
    try {
      if (typeof GM_setValue === 'function') {
        GM_setValue(TOKEN_KEY, cachedToken);
        return;
      }
    } catch (_) {}
    await sendExtensionMessage({ type: 'bilicast.storage.set', key: TOKEN_KEY, value: cachedToken });
  }

  async function gmRequest(opts) {
    try {
      if (typeof GM_xmlhttpRequest === 'function') {
        return await new Promise((resolve) => {
          GM_xmlhttpRequest({
            method: opts.method || 'GET',
            url: opts.url,
            headers: opts.headers || {},
            data: opts.data,
            timeout: opts.timeout || 8000,
            responseType: opts.responseType || 'text',
            onload: (res) => resolve({ ok: res.status >= 200 && res.status < 300, status: res.status, body: res.response, text: res.responseText }),
            onerror: () => resolve({ ok: false, status: 0, error: 'network' }),
            ontimeout: () => resolve({ ok: false, status: 0, error: 'timeout' }),
          });
        });
      }
    } catch (_) {}

    const viaExtension = await sendExtensionMessage({
      type: 'bilicast.request',
      request: {
        method: opts.method || 'GET',
        url: opts.url,
        headers: opts.headers || {},
        data: opts.data,
        timeout: opts.timeout || 8000,
      },
    });
    if (viaExtension) return viaExtension;

    try {
      const controller = new AbortController();
      const timer = setTimeout(() => controller.abort(), opts.timeout || 8000);
      const res = await fetch(opts.url, {
        method: opts.method || 'GET',
        headers: opts.headers || {},
        body: opts.data,
        signal: controller.signal,
        credentials: 'omit',
      });
      clearTimeout(timer);
      const text = await res.text();
      return { ok: res.status >= 200 && res.status < 300, status: res.status, body: text, text };
    } catch (e) {
      return { ok: false, status: 0, error: e && e.name === 'AbortError' ? 'timeout' : 'network' };
    }
  }

  async function requestLocalApi(path, { method = 'GET', payload = null, withToken = false, timeout = 12000 } = {}) {
    const headers = { 'Accept': 'application/json' };
    if (payload) headers['Content-Type'] = 'application/json';
    if (withToken) {
      const tok = await getLocalToken();
      if (tok) headers['X-BiliCast-Token'] = tok;
    }
    const r = await gmRequest({
      method,
      url: LOCAL_API + path,
      headers,
      data: payload ? JSON.stringify(payload) : undefined,
      timeout,
    });
    let data = null;
    try { data = r.text ? JSON.parse(r.text) : null; } catch (_) {}
    return { ok: r.ok, status: r.status, data, networkError: r.error };
  }

  // --- MD5 (public domain, Paul Johnston / Joseph Myers based) ---------------

  function md5(s) {
    function safeAdd(x, y) {
      const lsw = (x & 0xFFFF) + (y & 0xFFFF);
      const msw = (x >> 16) + (y >> 16) + (lsw >> 16);
      return (msw << 16) | (lsw & 0xFFFF);
    }
    function bitRol(n, c) { return (n << c) | (n >>> (32 - c)); }
    function md5cmn(q, a, b, x, s, t) {
      return safeAdd(bitRol(safeAdd(safeAdd(a, q), safeAdd(x, t)), s), b);
    }
    function md5ff(a, b, c, d, x, s, t) { return md5cmn((b & c) | ((~b) & d), a, b, x, s, t); }
    function md5gg(a, b, c, d, x, s, t) { return md5cmn((b & d) | (c & (~d)), a, b, x, s, t); }
    function md5hh(a, b, c, d, x, s, t) { return md5cmn(b ^ c ^ d, a, b, x, s, t); }
    function md5ii(a, b, c, d, x, s, t) { return md5cmn(c ^ (b | (~d)), a, b, x, s, t); }
    function binlMD5(x, len) {
      x[len >> 5] |= 0x80 << (len % 32);
      x[(((len + 64) >>> 9) << 4) + 14] = len;
      let a = 1732584193, b = -271733879, c = -1732584194, d = 271733878;
      for (let i = 0; i < x.length; i += 16) {
        const oa = a, ob = b, oc = c, od = d;
        a = md5ff(a, b, c, d, x[i+0],  7, -680876936);
        d = md5ff(d, a, b, c, x[i+1],  12, -389564586);
        c = md5ff(c, d, a, b, x[i+2],  17, 606105819);
        b = md5ff(b, c, d, a, x[i+3],  22, -1044525330);
        a = md5ff(a, b, c, d, x[i+4],  7, -176418897);
        d = md5ff(d, a, b, c, x[i+5],  12, 1200080426);
        c = md5ff(c, d, a, b, x[i+6],  17, -1473231341);
        b = md5ff(b, c, d, a, x[i+7],  22, -45705983);
        a = md5ff(a, b, c, d, x[i+8],  7, 1770035416);
        d = md5ff(d, a, b, c, x[i+9],  12, -1958414417);
        c = md5ff(c, d, a, b, x[i+10], 17, -42063);
        b = md5ff(b, c, d, a, x[i+11], 22, -1990404162);
        a = md5ff(a, b, c, d, x[i+12], 7, 1804603682);
        d = md5ff(d, a, b, c, x[i+13], 12, -40341101);
        c = md5ff(c, d, a, b, x[i+14], 17, -1502002290);
        b = md5ff(b, c, d, a, x[i+15], 22, 1236535329);
        a = md5gg(a, b, c, d, x[i+1],  5, -165796510);
        d = md5gg(d, a, b, c, x[i+6],  9, -1069501632);
        c = md5gg(c, d, a, b, x[i+11], 14, 643717713);
        b = md5gg(b, c, d, a, x[i+0],  20, -373897302);
        a = md5gg(a, b, c, d, x[i+5],  5, -701558691);
        d = md5gg(d, a, b, c, x[i+10], 9, 38016083);
        c = md5gg(c, d, a, b, x[i+15], 14, -660478335);
        b = md5gg(b, c, d, a, x[i+4],  20, -405537848);
        a = md5gg(a, b, c, d, x[i+9],  5, 568446438);
        d = md5gg(d, a, b, c, x[i+14], 9, -1019803690);
        c = md5gg(c, d, a, b, x[i+3],  14, -187363961);
        b = md5gg(b, c, d, a, x[i+8],  20, 1163531501);
        a = md5gg(a, b, c, d, x[i+13], 5, -1444681467);
        d = md5gg(d, a, b, c, x[i+2],  9, -51403784);
        c = md5gg(c, d, a, b, x[i+7],  14, 1735328473);
        b = md5gg(b, c, d, a, x[i+12], 20, -1926607734);
        a = md5hh(a, b, c, d, x[i+5],  4, -378558);
        d = md5hh(d, a, b, c, x[i+8],  11, -2022574463);
        c = md5hh(c, d, a, b, x[i+11], 16, 1839030562);
        b = md5hh(b, c, d, a, x[i+14], 23, -35309556);
        a = md5hh(a, b, c, d, x[i+1],  4, -1530992060);
        d = md5hh(d, a, b, c, x[i+4],  11, 1272893353);
        c = md5hh(c, d, a, b, x[i+7],  16, -155497632);
        b = md5hh(b, c, d, a, x[i+10], 23, -1094730640);
        a = md5hh(a, b, c, d, x[i+13], 4, 681279174);
        d = md5hh(d, a, b, c, x[i+0],  11, -358537222);
        c = md5hh(c, d, a, b, x[i+3],  16, -722521979);
        b = md5hh(b, c, d, a, x[i+6],  23, 76029189);
        a = md5hh(a, b, c, d, x[i+9],  4, -640364487);
        d = md5hh(d, a, b, c, x[i+12], 11, -421815835);
        c = md5hh(c, d, a, b, x[i+15], 16, 530742520);
        b = md5hh(b, c, d, a, x[i+2],  23, -995338651);
        a = md5ii(a, b, c, d, x[i+0],  6, -198630844);
        d = md5ii(d, a, b, c, x[i+7],  10, 1126891415);
        c = md5ii(c, d, a, b, x[i+14], 15, -1416354905);
        b = md5ii(b, c, d, a, x[i+5],  21, -57434055);
        a = md5ii(a, b, c, d, x[i+12], 6, 1700485571);
        d = md5ii(d, a, b, c, x[i+3],  10, -1894986606);
        c = md5ii(c, d, a, b, x[i+10], 15, -1051523);
        b = md5ii(b, c, d, a, x[i+1],  21, -2054922799);
        a = md5ii(a, b, c, d, x[i+8],  6, 1873313359);
        d = md5ii(d, a, b, c, x[i+15], 10, -30611744);
        c = md5ii(c, d, a, b, x[i+6],  15, -1560198380);
        b = md5ii(b, c, d, a, x[i+13], 21, 1309151649);
        a = md5ii(a, b, c, d, x[i+4],  6, -145523070);
        d = md5ii(d, a, b, c, x[i+11], 10, -1120210379);
        c = md5ii(c, d, a, b, x[i+2],  15, 718787259);
        b = md5ii(b, c, d, a, x[i+9],  21, -343485551);
        a = safeAdd(a, oa);
        b = safeAdd(b, ob);
        c = safeAdd(c, oc);
        d = safeAdd(d, od);
      }
      return [a, b, c, d];
    }
    function binl2hex(arr) {
      const hex = '0123456789abcdef';
      let str = '';
      for (let i = 0; i < arr.length * 4; i++) {
        str += hex.charAt((arr[i >> 2] >> ((i % 4) * 8 + 4)) & 0xF) +
               hex.charAt((arr[i >> 2] >> ((i % 4) * 8)) & 0xF);
      }
      return str;
    }
    function str2binl(str) {
      const bin = [];
      const mask = (1 << 8) - 1;
      for (let i = 0; i < str.length * 8; i += 8)
        bin[i >> 5] |= (str.charCodeAt(i / 8) & mask) << (i % 32);
      return bin;
    }
    s = unescape(encodeURIComponent(s));
    return binl2hex(binlMD5(str2binl(s), s.length * 8));
  }

  // --- shadow host -----------------------------------------------------------

  let shadowRoot = null;
  let useShadow = true; // disabled if attachShadow throws on this page
  function ensureShadowHost() {
    if (!useShadow) return ensurePlainHost();
    if (shadowRoot && shadowRoot.host && shadowRoot.host.isConnected) {
      return shadowRoot;
    }
    // Stale or first run — purge any leftover host from previous script runs.
    document.querySelectorAll('#' + HOST_ID).forEach((el) => el.remove());
    const host = document.createElement('div');
    host.id = HOST_ID;
    host.style.cssText = 'all:initial;position:fixed;top:0;left:0;width:0;height:0;z-index:2147483647;';
    (document.body || document.documentElement).appendChild(host);
    try {
      shadowRoot = host.attachShadow({ mode: 'open' });
    } catch (e) {
      console.warn('[BiliCast] attachShadow failed, falling back to plain DOM', e);
      useShadow = false;
      host.remove();
      return ensurePlainHost();
    }
    const style = document.createElement('style');
    style.textContent = `
      .toast-stack {
        position: fixed; top: 72px; right: 24px;
        display: flex; flex-direction: column; gap: 8px;
        font: 13px/1.4 -apple-system, "PingFang SC", "Microsoft YaHei", sans-serif;
        pointer-events: none;
      }
      .toast {
        max-width: 360px; padding: 10px 14px; border-radius: 10px;
        color: #fff; box-shadow: 0 6px 20px rgba(0,0,0,.25);
        background: #303030; opacity: 0; transform: translateY(-6px);
        transition: opacity .2s ease, transform .2s ease;
        pointer-events: auto;
        white-space: pre-wrap;
      }
      .toast.show { opacity: 1; transform: translateY(0); }
      .toast.info  { background: #2b6cb0; }
      .toast.ok    { background: #2f855a; }
      .toast.warn  { background: #b7791f; }
      .toast.error { background: #c53030; }
      .cast-btn {
        position: fixed; right: 24px; bottom: 96px;
        display: inline-flex; align-items: center; gap: 6px;
        padding: 8px 14px; border-radius: 999px; border: none;
        background: #fb7299; color: #fff; cursor: pointer;
        font: 600 13px/1 -apple-system, "PingFang SC", sans-serif;
        box-shadow: 0 4px 14px rgba(251,114,153,.45);
      }
      .cast-btn:hover  { background: #ff85ad; }
      .cast-btn:active { background: #e25e84; transform: translateY(1px); }
      .cast-btn[disabled] { opacity: .6; cursor: progress; }
      .cast-btn .icon {
        display: inline-flex; align-items: center; justify-content: center;
        width: 14px; height: 14px;
      }
      .cast-btn .icon svg { width: 14px; height: 14px; }

      .picker-mask {
        position: fixed; inset: 0; background: rgba(0,0,0,.4);
        display: flex; align-items: center; justify-content: center;
        z-index: 2147483646;
        font: 13px/1.4 -apple-system, "PingFang SC", "Microsoft YaHei", sans-serif;
      }
      .picker {
        background: #fff; color: #18191c;
        width: 380px; max-width: calc(100vw - 32px);
        max-height: 80vh; overflow: hidden;
        border-radius: 14px; box-shadow: 0 16px 48px rgba(0,0,0,.3);
        display: flex; flex-direction: column;
      }
      .picker-head {
        display: flex; align-items: center; justify-content: space-between;
        padding: 14px 18px; border-bottom: 1px solid #e3e5e7;
      }
      .picker-title { font-weight: 600; font-size: 14px; }
      .picker-close {
        cursor: pointer; border: none; background: transparent;
        font-size: 18px; color: #61666d;
      }
      .picker-body {
        padding: 8px; overflow: auto; max-height: 60vh;
      }
      .picker-empty { padding: 24px; text-align: center; color: #61666d; }
      .device-item {
        display: flex; align-items: center; gap: 10px;
        padding: 10px 12px; border-radius: 8px; cursor: pointer;
      }
      .device-item:hover { background: #f4f5f7; }
      .device-item .icon {
        display: inline-flex; align-items: center; justify-content: center;
        width: 24px; height: 24px; color: #61666d;
      }
      .device-item .meta { display: flex; flex-direction: column; gap: 2px; min-width: 0; }
      .device-item .name { font-weight: 600; }
      .device-item .sub  { color: #61666d; font-size: 12px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
      .picker-foot {
        display: flex; gap: 8px; justify-content: flex-end;
        padding: 12px 18px; border-top: 1px solid #e3e5e7;
      }
      .btn {
        border: 1px solid #d6d8db; background: #fff; color: #18191c;
        padding: 6px 12px; border-radius: 6px; cursor: pointer;
        font: inherit;
      }
      .btn:hover { background: #f4f5f7; }
      .btn.primary { background: #fb7299; border-color: #fb7299; color: #fff; }
      .btn.primary:hover { background: #ff85ad; border-color: #ff85ad; }
      .btn:disabled { opacity: .6; cursor: progress; }
      .btn.btn-token { color: #61666d; border-color: transparent; background: transparent; }
      .btn.btn-token:hover { background: #f4f5f7; border-color: #d6d8db; }
    `;
    shadowRoot.appendChild(style);
    const toastStack = document.createElement('div');
    toastStack.className = 'toast-stack';
    shadowRoot.appendChild(toastStack);
    return shadowRoot;
  }

  // Plain-DOM fallback: same surface (`getElementById`, `appendChild`, `querySelector`)
  // exposed via a wrapper so the rest of the script can stay agnostic.
  let plainHost = null;
  function ensurePlainHost() {
    if (plainHost && plainHost.isConnected) return wrapPlainHost(plainHost);
    document.querySelectorAll('#' + HOST_ID + '-plain').forEach((el) => el.remove());
    const host = document.createElement('div');
    host.id = HOST_ID + '-plain';
    host.style.cssText = 'position:fixed;top:0;left:0;width:0;height:0;z-index:2147483647;';
    (document.body || document.documentElement).appendChild(host);
    // Inject styles globally (no shadow). Class-prefixed to avoid clashes.
    if (!document.getElementById(HOST_ID + '-style')) {
      const style = document.createElement('style');
      style.id = HOST_ID + '-style';
      style.textContent = `
        #${HOST_ID}-plain .toast-stack {
          position: fixed; top: 72px; right: 24px;
          display: flex; flex-direction: column; gap: 8px;
          font: 13px/1.4 -apple-system, "PingFang SC", sans-serif;
          pointer-events: none; z-index: 2147483647;
        }
        #${HOST_ID}-plain .toast {
          max-width: 360px; padding: 10px 14px; border-radius: 10px;
          color: #fff; box-shadow: 0 6px 20px rgba(0,0,0,.25);
          background: #303030; opacity: 0; transform: translateY(-6px);
          transition: opacity .2s ease, transform .2s ease;
          pointer-events: auto; white-space: pre-wrap;
        }
        #${HOST_ID}-plain .toast.show  { opacity: 1; transform: translateY(0); }
        #${HOST_ID}-plain .toast.info  { background: #2b6cb0; }
        #${HOST_ID}-plain .toast.ok    { background: #2f855a; }
        #${HOST_ID}-plain .toast.warn  { background: #b7791f; }
        #${HOST_ID}-plain .toast.error { background: #c53030; }
        #${HOST_ID}-plain .cast-btn {
          position: fixed !important; right: 24px !important; bottom: 96px !important;
          display: inline-flex !important; align-items: center; gap: 6px;
          padding: 8px 14px !important; border-radius: 999px !important; border: none !important;
          background: #fb7299 !important; color: #fff !important; cursor: pointer !important;
          font: 600 13px/1 -apple-system, "PingFang SC", sans-serif !important;
          box-shadow: 0 4px 14px rgba(251,114,153,.45) !important;
          z-index: 2147483647 !important;
        }
        #${HOST_ID}-plain .cast-btn:hover  { background: #ff85ad !important; }
        #${HOST_ID}-plain .cast-btn[disabled] { opacity: .6; cursor: progress; }
      `;
      document.head.appendChild(style);
    }
    const toastStack = document.createElement('div');
    toastStack.className = 'toast-stack';
    host.appendChild(toastStack);
    plainHost = host;
    return wrapPlainHost(host);
  }

  // Mimic ShadowRoot's getElementById / querySelector / appendChild surface so
  // the rest of the script doesn't have to branch.
  function wrapPlainHost(host) {
    return {
      _host: host,
      getElementById: (id) => host.querySelector('#' + CSS.escape(id)),
      querySelector: (sel) => host.querySelector(sel),
      appendChild: (el) => host.appendChild(el),
    };
  }

  function showToast(message, type = 'info') {
    const root = ensureShadowHost();
    const stack = root.querySelector('.toast-stack');
    const node = document.createElement('div');
    node.className = `toast ${type}`;
    node.textContent = message;
    stack.appendChild(node);
    requestAnimationFrame(() => node.classList.add('show'));
    setTimeout(() => {
      node.classList.remove('show');
      setTimeout(() => node.remove(), 250);
    }, TOAST_TIMEOUT_MS);
  }

  // --- device picker modal ---------------------------------------------------

  function showDevicePicker({ devices, onSelect, onRefresh, onResetToken }) {
    const root = ensureShadowHost();
    const old = root.querySelector('.picker-mask');
    if (old) old.remove();

    const mask = document.createElement('div');
    mask.className = 'picker-mask';
    mask.addEventListener('click', (e) => { if (e.target === mask) mask.remove(); });

    const panel = document.createElement('div');
    panel.className = 'picker';

    const head = document.createElement('div');
    head.className = 'picker-head';
    const title = document.createElement('div');
    title.className = 'picker-title';
    title.textContent = '选择投屏设备';
    const close = document.createElement('button');
    close.className = 'picker-close';
    close.textContent = '×';
    close.addEventListener('click', () => mask.remove());
    head.appendChild(title);
    head.appendChild(close);

    const body = document.createElement('div');
    body.className = 'picker-body';

    function render(list) {
      body.innerHTML = '';
      if (!list || list.length === 0) {
        const empty = document.createElement('div');
        empty.className = 'picker-empty';
        empty.textContent = '没有发现设备。\n请确认电视和 Mac 在同一 Wi-Fi，并开启电视的 DLNA / 投屏功能，然后点"重新扫描"。';
        empty.style.whiteSpace = 'pre-wrap';
        body.appendChild(empty);
        return;
      }
      for (const dev of list) {
        const item = document.createElement('div');
        item.className = 'device-item';
        const icon = document.createElement('div');
        icon.className = 'icon';
        icon.innerHTML =
          '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round">' +
            '<rect x="2" y="4" width="20" height="14" rx="2"/>' +
            '<line x1="8" y1="20" x2="16" y2="20"/>' +
            '<line x1="12" y1="18" x2="12" y2="20"/>' +
          '</svg>';
        const meta = document.createElement('div');
        meta.className = 'meta';
        const name = document.createElement('div');
        name.className = 'name';
        name.textContent = dev.name || '(unnamed)';
        const sub = document.createElement('div');
        sub.className = 'sub';
        sub.textContent = [dev.manufacturer, dev.modelName].filter(Boolean).join(' · ') || dev.location || '';
        meta.appendChild(name);
        meta.appendChild(sub);
        item.appendChild(icon);
        item.appendChild(meta);
        item.addEventListener('click', () => {
          mask.remove();
          onSelect(dev);
        });
        body.appendChild(item);
      }
    }

    render(devices);

    const foot = document.createElement('div');
    foot.className = 'picker-foot';
    const refresh = document.createElement('button');
    refresh.className = 'btn';
    refresh.textContent = '重新扫描';
    refresh.addEventListener('click', async () => {
      refresh.disabled = true;
      const list = await onRefresh();
      refresh.disabled = false;
      render(list);
    });
    const cancel = document.createElement('button');
    cancel.className = 'btn';
    cancel.textContent = '取消';
    cancel.addEventListener('click', () => mask.remove());
    foot.appendChild(refresh);
    foot.appendChild(cancel);

    if (onResetToken) {
      const resetTok = document.createElement('button');
      resetTok.className = 'btn btn-token';
      resetTok.textContent = '设置 Token';
      resetTok.addEventListener('click', async () => {
        resetTok.disabled = true;
        const list = await onResetToken();
        resetTok.disabled = false;
        render(list);
      });
      foot.appendChild(resetTok);
    }

    panel.appendChild(head);
    panel.appendChild(body);
    panel.appendChild(foot);
    mask.appendChild(panel);
    root.appendChild(mask);
  }

  // --- B站 candidate gathering ----------------------------------------------

  function readWindowPlayinfo() {
    try {
      const win = (typeof unsafeWindow !== 'undefined') ? unsafeWindow : window;
      if (win.__playinfo__) return win.__playinfo__;
    } catch (_) {}
    const scripts = Array.from(document.querySelectorAll('script'));
    for (const s of scripts) {
      const t = s.textContent;
      if (!t) continue;
      const m = t.match(/window\.__playinfo__\s*=\s*(\{[\s\S]*?\});\s*<\/script>/) ||
                t.match(/window\.__playinfo__\s*=\s*(\{[\s\S]*?\});?$/m) ||
                t.match(/window\.__playinfo__\s*=\s*(\{[\s\S]*?\})\s*;/);
      if (m) {
        try { return JSON.parse(m[1]); } catch (_) {}
      }
    }
    return null;
  }

  function readWindowInitialState() {
    try {
      const win = (typeof unsafeWindow !== 'undefined') ? unsafeWindow : window;
      if (win.__INITIAL_STATE__) return win.__INITIAL_STATE__;
    } catch (_) {}
    const scripts = Array.from(document.querySelectorAll('script'));
    for (const s of scripts) {
      const t = s.textContent;
      if (!t) continue;
      const m = t.match(/window\.__INITIAL_STATE__\s*=\s*(\{[\s\S]*?\});\(function\(\)/) ||
                t.match(/window\.__INITIAL_STATE__\s*=\s*(\{[\s\S]*?\})\s*;/);
      if (m) {
        try { return JSON.parse(m[1]); } catch (_) {}
      }
    }
    return null;
  }

  function extractCidAndAid() {
    const init = readWindowInitialState();
    if (!init) return null;
    const v = init.videoData || init.video?.viewInfo || init.viewInfo || {};
    const aid = v.aid || init.aid;
    const cid = v.cid || init.cid;
    if (aid && cid) return { aid, cid };
    return null;
  }

  // 1) Reads __playinfo__ for whatever the page already has (DASH common, durl rare).
  function gatherFromPlayinfo(out) {
    const playinfo = readWindowPlayinfo();
    if (!playinfo) return;
    const data = playinfo.data || playinfo.result || playinfo;
    if (Array.isArray(data.durl)) {
      for (const d of data.durl) {
        if (d.url) out.push({ url: d.url, kind: 'mp4', quality: data.quality || 0, mime: 'video/mp4' });
        if (Array.isArray(d.backup_url)) for (const bu of d.backup_url) {
          if (bu) out.push({ url: bu, kind: 'mp4', quality: data.quality || 0, mime: 'video/mp4' });
        }
      }
    }
    if (data.dash) {
      if (Array.isArray(data.dash.video)) {
        for (const v of data.dash.video) {
          const u = v.baseUrl || v.base_url;
          if (u) out.push({
            url: u,
            kind: 'dash-video',
            quality: v.id || 0,
            mime: v.mimeType || v.mime_type || null,
            codec: v.codecs || v.codecid || null,
          });
        }
      }
      if (Array.isArray(data.dash.audio)) {
        for (const a of data.dash.audio) {
          const u = a.baseUrl || a.base_url;
          if (u) out.push({
            url: u,
            kind: 'dash-audio',
            quality: a.id || 0,
            mime: a.mimeType || a.mime_type || null,
            codec: a.codecs || null,
          });
        }
      }
    }
  }

  // 2) playurl?platform=html5 — tries fnval=0 then fnval=1, qn=120 (caps server-side at 720P).
  async function fetchMp4Candidates(ids) {
    const out = [];
    for (const fnval of [0, 1]) {
      const url = `https://api.bilibili.com/x/player/playurl?avid=${ids.aid}&cid=${ids.cid}&qn=120&fnval=${fnval}&fnver=0&fourk=1&platform=html5&high_quality=1`;
      const res = await gmRequest({
        method: 'GET',
        url,
        headers: { 'Referer': 'https://www.bilibili.com/' },
        timeout: 8000,
      });
      if (!res.ok) continue;
      try {
        const json = JSON.parse(res.text);
        const data = json?.data || json?.result || {};
        for (const d of (data.durl || [])) {
          if (d.url) out.push({ url: d.url, kind: 'mp4', quality: data.quality || 0, mime: 'video/mp4' });
          if (Array.isArray(d.backup_url)) for (const bu of d.backup_url) {
            if (bu) out.push({ url: bu, kind: 'mp4', quality: data.quality || 0, mime: 'video/mp4' });
          }
        }
        if (out.length) break;
      } catch (_) {}
    }
    return out;
  }

  // 3) TV-signed playurl — experimental. Aim is 1080P FLV.
  // Endpoint: api.bilibili.com/x/playurl with platform=android_tv_yst + appkey + ts + sign.
  async function fetchFlvTVCandidates(ids) {
    try {
      const ts = Math.floor(Date.now() / 1000);
      // Note: keys must be sorted alphabetically for the sign.
      const params = {
        appkey: TV_APPKEY,
        avid: ids.aid,
        cid: ids.cid,
        fnval: 0,
        fnver: 0,
        fourk: 1,
        otype: 'json',
        platform: 'android_tv_yst',
        qn: 120,
        ts,
      };
      const sortedKeys = Object.keys(params).sort();
      const queryString = sortedKeys.map((k) => `${k}=${encodeURIComponent(params[k])}`).join('&');
      const sign = md5(queryString + TV_APPSEC);
      const url = `https://api.bilibili.com/x/playurl?${queryString}&sign=${sign}`;
      const res = await gmRequest({
        method: 'GET',
        url,
        headers: { 'Referer': 'https://www.bilibili.com/' },
        timeout: 8000,
      });
      if (!res.ok) return [];
      const json = JSON.parse(res.text);
      if (json?.code !== 0) return [];
      const data = json.data || json.result || {};
      const out = [];
      const looksLikeFlv = (data.format || '').toLowerCase().includes('flv') ||
                          (data.durl?.[0]?.url || '').match(/\.flv(\?|$)/);
      const kind = looksLikeFlv ? 'flv' : 'mp4';
      for (const d of (data.durl || [])) {
        if (d.url) out.push({
          url: d.url,
          kind,
          quality: data.quality || 0,
          mime: kind === 'flv' ? 'video/x-flv' : 'video/mp4',
        });
        if (Array.isArray(d.backup_url)) for (const bu of d.backup_url) {
          if (bu) out.push({
            url: bu,
            kind,
            quality: data.quality || 0,
            mime: kind === 'flv' ? 'video/x-flv' : 'video/mp4',
          });
        }
      }
      return out;
    } catch (_) {
      return [];
    }
  }

  async function gatherCandidates() {
    const candidates = [];
    gatherFromPlayinfo(candidates);

    const ids = extractCidAndAid();
    if (ids) {
      const [mp4Cands, flvCands] = await Promise.all([
        fetchMp4Candidates(ids).catch(() => []),
        fetchFlvTVCandidates(ids).catch(() => []),
      ]);
      candidates.push(...mp4Cands, ...flvCands);
    }
    return candidates;
  }

  // --- main flow --------------------------------------------------------------

  let lastSelectedDeviceId = null;

  async function fetchDevices() {
    const r = await requestLocalApi('/api/devices', { withToken: true });
    if (!r.ok) return [];
    return r.data?.data?.devices || [];
  }

  async function refreshDevicesNow() {
    const r = await requestLocalApi('/api/devices/refresh', { method: 'POST', withToken: true, timeout: 12000 });
    if (!r.ok) return [];
    return await fetchDevices();
  }

  async function ensureToken() {
    const cur = await getLocalToken();
    if (cur) return cur;
    const v = prompt('请粘贴 BiliCast 菜单栏里的 Pairing Token：', '');
    if (!v) return '';
    const trimmed = v.trim();
    await setLocalToken(trimmed);
    return trimmed;
  }

  async function onCastClick() {
    const root = ensureShadowHost();
    const btn = root.getElementById(BUTTON_ID);
    if (!btn || btn.hasAttribute('disabled')) return;
    btn.setAttribute('disabled', '');

    try {
      if (isBangumiPage()) {
        showToast('当前内容可能受版权或 DRM 限制，第一版暂不支持。建议使用 HDMI / AirPlay / 系统镜像。', 'warn');
        return;
      }

      const health = await requestLocalApi('/api/health');
      if (!health.ok || health.data?.ok !== true) {
        showToast('未检测到 BiliCast，请先启动菜单栏 App。', 'error');
        return;
      }

      const token = await ensureToken();
      if (!token) {
        showToast('未设置 Token，无法继续。', 'error');
        return;
      }

      let devices = await fetchDevices();
      if (devices.length === 0) {
        // Check if the token is still valid before triggering a scan.
        const ps = await requestLocalApi('/api/pairing/status', { withToken: true });
        if (!ps.ok || ps.data?.data?.paired !== true) {
          await setLocalToken('');
          showToast('Token 已失效（可能后端已重启），请重新设置。', 'warn');
        }
        showToast('正在搜索局域网设备…', 'info');
        devices = await refreshDevicesNow();
      }

      showDevicePicker({
        devices,
        onSelect: (dev) => {
          lastSelectedDeviceId = dev.id;
          startCast(dev);
        },
        onRefresh: async () => {
          showToast('正在搜索局域网设备…', 'info');
          return await refreshDevicesNow();
        },
        onResetToken: async () => {
          const cur = await getLocalToken();
          const v = prompt('粘贴菜单栏 App 里的 token：', cur);
          if (v == null) return [];
          await setLocalToken(v.trim());
          showToast('Token 已保存。', 'ok');
          return await refreshDevicesNow();
        },
      });
    } finally {
      btn.removeAttribute('disabled');
    }
  }

  async function startCast(dev) {
    showToast(`正在为「${dev.name}」准备视频流…`, 'info');
    const candidates = await gatherCandidates();
    if (!candidates.length) {
      showToast('当前视频暂不支持投屏：拿不到任何可播放流。可能是会员/版权/DRM 内容。', 'error');
      return;
    }
    const summary = summarizeCandidates(candidates);
    const payload = {
      deviceId: dev.id,
      pageUrl: location.href,
      bv: extractBvFromUrl(),
      title: getVideoTitle(),
      currentTime: getCurrentTime(),
      candidates,
      source: 'tampermonkey',
    };
    const r = await requestLocalApi('/api/cast', { method: 'POST', payload, withToken: true, timeout: 20000 });
    if (r.ok && r.data?.ok) {
      const d = r.data.data;
      const tier = d.tier || '?';
      showToast(`已投到「${d.deviceName}」（清晰度档：${tier}）：${d.title}\n候选 ${summary}`, 'ok');
    } else {
      const code = r.data?.error?.code || `HTTP ${r.status}`;
      const msg = r.data?.error?.message || r.networkError || '未知错误';
      showToast(`投屏失败（${code}）：${msg}\n采集到的候选：${summary}`, 'error');
    }
  }

  function summarizeCandidates(list) {
    const counts = {};
    for (const c of list) counts[c.kind] = (counts[c.kind] || 0) + 1;
    return Object.entries(counts).map(([k, n]) => `${k}×${n}`).join(', ');
  }

  // --- button -----------------------------------------------------------------

  // Material-design "cast" icon; cleaner than the 📺 emoji.
  const CAST_ICON_SVG =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="14" height="14" fill="currentColor" aria-hidden="true">' +
      '<path d="M21 3H3c-1.1 0-2 .9-2 2v3h2V5h18v14h-7v2h7c1.1 0 2-.9 2-2V5c0-1.1-.9-2-2-2zM1 18v3h3c0-1.66-1.34-3-3-3zm0-4v2c2.76 0 5 2.24 5 5h2c0-3.87-3.13-7-7-7zm0-4v2c4.97 0 9 4.03 9 9h2c0-6.07-4.92-11-11-11z"/>' +
    '</svg>';

  function injectCastButton() {
    const root = ensureShadowHost();
    if (root.getElementById(BUTTON_ID)) return false;
    const btn = document.createElement('button');
    btn.id = BUTTON_ID;
    btn.className = 'cast-btn';
    btn.innerHTML = '<span class="icon">' + CAST_ICON_SVG + '</span><span class="label">投屏</span>';
    btn.addEventListener('click', onCastClick);
    root.appendChild(btn);
    console.info('[BiliCast] cast button injected (shadow=' + useShadow + ')');
    return true;
  }

  // --- token entry / utility commands ----------------------------------------

  try {
    GM_registerMenuCommand('设置 BiliCast Token', async () => {
      const cur = await getLocalToken();
      const v = prompt('粘贴菜单栏 App 里的 token：', cur);
      if (v == null) return;
      await setLocalToken(v.trim());
      showToast('Token 已保存。', 'ok');
    });
    GM_registerMenuCommand('清除 BiliCast Token', async () => {
      await setLocalToken('');
      showToast('Token 已清除。', 'info');
    });
    GM_registerMenuCommand('停止当前投屏', async () => {
      if (!lastSelectedDeviceId) {
        showToast('当前没有记录到正在投屏的设备。', 'info');
        return;
      }
      const r = await requestLocalApi('/api/cast/stop', {
        method: 'POST',
        payload: { deviceId: lastSelectedDeviceId },
        withToken: true,
      });
      if (r.ok && r.data?.ok) showToast('已发送停止指令。', 'ok');
      else showToast('停止失败：' + (r.data?.error?.message || r.networkError || '未知'), 'error');
    });
    GM_registerMenuCommand('查看候选诊断', async () => {
      const candidates = await gatherCandidates();
      const summary = summarizeCandidates(candidates);
      console.info('[BiliCast] candidates:', candidates);
      showToast(`候选采集：${summary}\n详见控制台。`, 'info');
    });
  } catch (_) {}

  // --- bootstrap --------------------------------------------------------------

  let lastDiag = '';
  function diag(msg) {
    if (msg !== lastDiag) {
      lastDiag = msg;
      console.info('[BiliCast] ' + msg);
    }
  }

  function maybeInject() {
    const isVideo = isBilibiliVideoPage();
    const isBangumi = isBangumiPage();
    if (!isVideo && !isBangumi) {
      diag('skip injection: pathname=' + location.pathname);
      return;
    }
    try {
      injectCastButton();
    } catch (e) {
      console.warn('[BiliCast] inject error', e);
    }
  }

  function bootstrap() {
    maybeInject();

    // Re-inject if B站 SPA / extensions yank our host. Fast for the first 30s,
    // then settle into a slower heartbeat.
    let fastTicks = 0;
    const fast = setInterval(() => {
      maybeInject();
      if (++fastTicks >= 20) clearInterval(fast);  // ~30s
    }, 1500);
    setInterval(maybeInject, 5000);

    // Detect SPA route changes.
    let lastHref = location.href;
    const observer = new MutationObserver(() => {
      if (location.href !== lastHref) {
        lastHref = location.href;
        maybeInject();
      }
    });
    if (document.body) {
      observer.observe(document.body, { childList: true, subtree: true });
    } else {
      // body not ready yet — wait for it
      const wait = new MutationObserver(() => {
        if (document.body) {
          wait.disconnect();
          observer.observe(document.body, { childList: true, subtree: true });
        }
      });
      wait.observe(document.documentElement, { childList: true });
    }
  }

  console.info('[BiliCast] v0.3.3 loaded; pathname=' + location.pathname +
               '; isVideoPage=' + isBilibiliVideoPage() +
               '; isBangumiPage=' + isBangumiPage());
  bootstrap();
})();
