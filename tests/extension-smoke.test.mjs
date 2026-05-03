import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';
import vm from 'node:vm';

function syntaxCheck(source, filename) {
  new vm.Script(source, { filename });
}

function createElement(tagName = 'div') {
  const children = [];
  const element = {
    tagName: tagName.toUpperCase(),
    children,
    attributes: {},
    style: {},
    className: '',
    id: '',
    textContent: '',
    innerHTML: '',
    isConnected: true,
    setAttribute(name, value) { this.attributes[name] = String(value ?? ''); },
    getAttribute(name) { return this.attributes[name] ?? null; },
    hasAttribute(name) { return Object.hasOwn(this.attributes, name); },
    removeAttribute(name) { delete this.attributes[name]; },
    appendChild(child) { child.parentNode = this; child.isConnected = true; children.push(child); return child; },
    remove() { this.isConnected = false; },
    addEventListener() {},
    querySelector(selector) {
      if (selector === '.toast-stack') return children.find((child) => child.className === 'toast-stack') || null;
      if (selector.startsWith('#')) return children.find((child) => child.id === selector.slice(1)) || null;
      return null;
    },
    querySelectorAll() { return []; },
    attachShadow() {
      const shadowChildren = [];
      const shadow = {
        host: element,
        children: shadowChildren,
        appendChild(child) { child.parentNode = this; child.isConnected = true; shadowChildren.push(child); return child; },
        querySelector(selector) {
          if (selector === '.toast-stack') return shadowChildren.find((child) => child.className === 'toast-stack') || null;
          if (selector === '.picker-mask') return shadowChildren.find((child) => child.className === 'picker-mask') || null;
          return null;
        },
        getElementById(id) { return shadowChildren.find((child) => child.id === id) || null; },
      };
      element.shadowRoot = shadow;
      return shadow;
    },
  };
  return element;
}

test('extension manifest declares content script, storage, and bridge hosts', async () => {
  const manifest = JSON.parse(await readFile('extension/manifest.json', 'utf8'));
  assert.equal(manifest.manifest_version, 3);
  assert.deepEqual(manifest.permissions, ['storage']);
  assert.ok(manifest.host_permissions.includes('http://127.0.0.1:18787/*'));
  assert.ok(manifest.host_permissions.includes('https://api.bilibili.com/*'));
  assert.equal(manifest.content_scripts[0].js[0], 'content.js');
  assert.ok(manifest.content_scripts[0].matches.includes('https://www.bilibili.com/video/*'));
});

test('browser extension content script is synced with the userscript implementation', async () => {
  const userscript = await readFile('userscript/bilicast-helper.user.js', 'utf8');
  const content = await readFile('extension/content.js', 'utf8');
  assert.equal(content, userscript);
});

test('javascript entry points parse successfully', async () => {
  for (const file of ['userscript/bilicast-helper.user.js', 'extension/content.js', 'extension/background.js', 'extension/popup.js']) {
    syntaxCheck(await readFile(file, 'utf8'), file);
  }
});

test('background bridge handles request and storage messages', async () => {
  let listener = null;
  const store = {};
  const context = {
    console,
    setTimeout,
    clearTimeout,
    chrome: {
      runtime: { onMessage: { addListener(fn) { listener = fn; } } },
      storage: {
        local: {
          get(defaults, cb) { cb({ ...defaults, ...store }); },
          set(values, cb) { Object.assign(store, values); cb(); },
        },
      },
    },
    fetch: async (url, init) => ({
      status: init.method === 'POST' ? 201 : 200,
      text: async () => JSON.stringify({ url, method: init.method }),
    }),
    AbortController,
  };
  vm.runInNewContext(await readFile('extension/background.js', 'utf8'), context, { filename: 'extension/background.js' });
  assert.equal(typeof listener, 'function');

  const send = (message) => new Promise((resolve) => listener(message, {}, resolve));
  assert.equal((await send({ type: 'bilicast.storage.set', key: 'bilicast.token', value: 'tok' })).ok, true);
  const stored = await send({ type: 'bilicast.storage.get', key: 'bilicast.token' });
  assert.equal(stored.ok, true);
  assert.equal(stored.value, 'tok');
  const response = await send({ type: 'bilicast.request', request: { method: 'POST', url: 'http://127.0.0.1:18787/api/health', data: '{}' } });
  assert.equal(response.ok, true);
  assert.equal(response.status, 201);
  assert.match(response.text, /api\/health/);
});

test('shared content script boots on a bilibili video page in extension context', async () => {
  const body = createElement('body');
  const head = createElement('head');
  const documentElement = createElement('html');
  const document = {
    body,
    head,
    documentElement,
    title: '测试视频_哔哩哔哩_bilibili',
    createElement,
    querySelector() { return null; },
    querySelectorAll() { return []; },
  };
  const context = {
    console: { info() {}, warn() {}, error() {} },
    window: {},
    document,
    location: { href: 'https://www.bilibili.com/video/BV1xx411c7mD', pathname: '/video/BV1xx411c7mD' },
    chrome: {
      runtime: {
        id: 'extension-id',
        sendMessage(_message, cb) { cb({ ok: true, value: '' }); },
      },
    },
    CSS: { escape: (value) => String(value).replace(/[^a-zA-Z0-9_-]/g, '\\$&') },
    MutationObserver: class { observe() {} disconnect() {} },
    setInterval() { return 1; },
    clearInterval() {},
    setTimeout() { return 1; },
    clearTimeout() {},
    requestAnimationFrame(cb) { cb(); },
    prompt() { return ''; },
    fetch: async () => ({ status: 200, text: async () => '{}' }),
    AbortController,
  };
  context.window = context;
  vm.runInNewContext(await readFile('extension/content.js', 'utf8'), context, { filename: 'extension/content.js' });
  const host = body.children.find((child) => child.id === 'bilicast-host');
  assert.ok(host, 'shadow host should be injected');
  assert.ok(host.shadowRoot.getElementById('bilicast-cast-btn'), 'cast button should be injected');
});
