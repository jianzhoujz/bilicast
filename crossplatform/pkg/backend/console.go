package backend

import (
	"net/http"
	"strings"
)

func (s *Service) handleConsole(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	html := strings.ReplaceAll(consoleHTML, "__VERSION__", Version)
	_, _ = w.Write([]byte(html))
}

const consoleHTML = `<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>BiliCast Console</title>
  <style>
    :root {
      color-scheme: light dark;
      --bg: #f6f7f8;
      --fg: #18191c;
      --muted: #6b7280;
      --line: #e3e5e7;
      --card: #ffffff;
      --card-soft: #f1f2f3;
      --accent: #fb7299;
      --warn: #d57400;
      --ok: #168348;
      --err: #d03050;
    }
    @media (prefers-color-scheme: dark) {
      :root {
        --bg: #1c1d22;
        --fg: #f1f2f3;
        --muted: #a5adba;
        --line: #34373f;
        --card: #25272d;
        --card-soft: #2f3138;
        --warn: #f0a040;
      }
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      color: var(--fg);
      background: var(--bg);
      font: 13px/1.45 -apple-system, BlinkMacSystemFont, "Segoe UI", "PingFang SC", sans-serif;
    }
    main { max-width: 720px; margin: 0 auto; padding: 14px 14px 22px; }
    .section { padding: 10px 0; border-bottom: 1px solid var(--line); }
    .section:last-child { border-bottom: 0; }
    .section-label {
      font-size: 11px; font-weight: 650; color: var(--muted);
      text-transform: uppercase; letter-spacing: .04em; margin: 0 0 4px;
    }
    .head {
      display: flex; align-items: center; justify-content: space-between;
      gap: 8px; margin-bottom: 6px;
    }
    .row { display: flex; align-items: center; gap: 6px; flex-wrap: wrap; }
    .grow { flex: 1; min-width: 0; }
    .mono { font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; }
    .muted { color: var(--muted); font-size: 12px; }
    .small { font-size: 11.5px; }
    .ok { color: var(--ok); }
    .warn { color: var(--warn); }
    .err { color: var(--err); }

    /* status header */
    .status-header { display: flex; align-items: center; gap: 8px; padding: 4px 0 8px; }
    .status-dot {
      width: 10px; height: 10px; border-radius: 50%;
      background: var(--muted); flex-shrink: 0;
    }
    .status-dot.running { background: var(--ok); box-shadow: 0 0 0 3px rgba(22,131,72,.18); }
    .status-dot.starting { background: var(--warn); }
    .status-dot.failed { background: var(--err); }
    .status-text { font-size: 14px; font-weight: 600; }

    /* buttons */
    .btn {
      border: 1px solid var(--line);
      background: var(--card);
      color: var(--fg);
      border-radius: 5px;
      padding: 3px 9px;
      font: inherit;
      font-size: 11.5px;
      cursor: pointer;
    }
    .btn:hover { background: var(--card-soft); }
    .btn:disabled { opacity: .55; cursor: not-allowed; }
    .btn.primary { background: var(--accent); border-color: var(--accent); color: #fff; }
    .btn.primary:hover { filter: brightness(.95); }
    .btn.danger { color: var(--err); border-color: var(--err); }
    .btn.danger:hover { background: rgba(208,48,80,.08); }

    /* form */
    input[type="text"], input[type="password"], select {
      width: 100%; padding: 5px 8px; border-radius: 5px;
      border: 1px solid var(--line); background: var(--card); color: inherit;
      font: inherit; font-size: 12px;
    }
    input:focus, select:focus { outline: 2px solid var(--accent); outline-offset: -1px; border-color: transparent; }

    /* badges */
    .badge {
      font-size: 10.5px; font-weight: 600;
      padding: 1px 6px; border-radius: 999px;
      background: var(--card-soft); color: var(--muted);
    }
    .badge.ok { color: var(--ok); }
    .badge.warn { color: var(--warn); }

    /* info card (quality details) */
    .info-card {
      background: var(--card-soft); border-radius: 6px;
      padding: 8px 10px; margin-top: 8px; font-size: 12px;
    }
    .info-card p { margin: 0 0 6px; }
    .info-card .pro, .info-card .con { display: flex; gap: 6px; align-items: flex-start; line-height: 1.45; }
    .info-card .pro::before { content: "+"; color: var(--ok); font-weight: 700; flex-shrink: 0; width: 10px; text-align: center; }
    .info-card .con::before { content: "−"; color: var(--warn); font-weight: 700; flex-shrink: 0; width: 10px; text-align: center; }
    .info-card .note { color: var(--warn); margin-top: 6px; font-size: 11.5px; }

    /* device list */
    .device-list { display: flex; flex-direction: column; gap: 2px; }
    .device-row { display: flex; align-items: center; gap: 8px; padding: 4px 0; }
    .device-icon {
      width: 22px; flex-shrink: 0; color: var(--muted);
      display: flex; justify-content: center; font-size: 14px;
    }
    .device-name { font-size: 12px; font-weight: 600; }
    .device-sub { font-size: 11px; color: var(--muted); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
    .empty { font-size: 12px; color: var(--muted); padding: 4px 0; }

    /* current session card */
    .session-title { font-size: 12.5px; font-weight: 600; line-height: 1.4; }
    .session-meta { font-size: 11.5px; color: var(--muted); margin-top: 2px; }

    /* token */
    .token-display {
      font-size: 11.5px; color: var(--muted);
      overflow: hidden; text-overflow: ellipsis; white-space: nowrap;
    }
    .token-input-row { display: none; gap: 6px; align-items: center; margin-top: 6px; }
    .token-input-row.show { display: flex; }
  </style>
</head>
<body>
  <main>
    <header class="status-header">
      <div id="status-dot" class="status-dot"></div>
      <div id="status-text" class="status-text">检查中…</div>
    </header>

    <section class="section">
      <p class="section-label">控制 API</p>
      <div class="mono small muted" id="control-addr">127.0.0.1:18787</div>
      <div class="mono small muted" id="proxy-addr">代理：0.0.0.0:18788</div>
    </section>

    <section class="section">
      <div class="head">
        <p class="section-label" style="margin:0">Pairing Token</p>
        <div class="row">
          <button class="btn" id="copy-token">复制</button>
          <button class="btn" id="edit-token">手动设置</button>
        </div>
      </div>
      <div class="token-display" id="token-display">(未设置)</div>
      <div class="token-input-row" id="token-input-row">
        <input id="token" type="password" autocomplete="off" placeholder="粘贴 token">
        <button class="btn primary" id="save-token">保存</button>
        <button class="btn" id="cancel-token">取消</button>
      </div>
      <div id="pairing" class="small muted" style="margin-top:4px">未检查</div>
    </section>

    <section class="section">
      <div class="head">
        <p class="section-label" style="margin:0">清晰度模式</p>
        <span id="ffmpeg-badge" class="badge">ffmpeg ?</span>
      </div>
      <select id="quality"></select>
      <div class="info-card" id="quality-info">
        <p id="quality-summary"></p>
        <div id="quality-pros-cons"></div>
        <div class="note" id="quality-note" style="display:none"></div>
      </div>
    </section>

    <section class="section">
      <div class="head">
        <p class="section-label" style="margin:0">DLNA 设备 <span class="muted small" id="device-count"></span></p>
        <button class="btn" id="refresh-devices">重新扫描</button>
      </div>
      <div id="devices" class="device-list"></div>
    </section>

    <section class="section" id="session-section" style="display:none">
      <div class="head">
        <p class="section-label" style="margin:0">当前投屏</p>
        <span class="badge" id="session-tier"></span>
      </div>
      <div class="session-title" id="session-title"></div>
      <div class="session-meta" id="session-meta"></div>
      <div class="row" style="justify-content:flex-end; margin-top:6px">
        <button class="btn danger" id="stop-cast">停止投屏</button>
      </div>
    </section>

    <section class="section">
      <p class="section-label">关于</p>
      <div class="muted small">BiliCast v__VERSION__</div>
      <div class="row" style="margin-top:6px">
        <a class="btn" href="https://github.com/jianzhoujz/bilicast" target="_blank" rel="noopener">GitHub 主页</a>
      </div>
    </section>
  </main>

  <script>
    const TOKEN_KEY = 'bilicast.token';
    const API_PREFIX = '/api/bilicast';

    // Native-style quality copy mirrored from BiliCastCore/QualityPreference.swift.
    const QUALITY_INFO = {
      mp4Safe: {
        displayName: '标准（720P MP4）',
        summary: '兼容性最好。所有视频都能投，但清晰度只到 720P。',
        pros: ['几乎所有公开视频都能投', '零额外依赖', 'B 站接口最稳定，不会突然失效'],
        cons: ['清晰度封顶 720P，再高的画质 B 站不给单文件'],
        note: null,
      },
      flvTV: {
        displayName: '高清（1080P FLV，实验性）',
        summary: '用 B 站 TV 接口拿 1080P FLV。可能因 B 站策略调整失效。',
        pros: ['原生 1080P FLV，画质明显好于标准模式', '电视直连 B 站 CDN，Mac 关了也能继续看'],
        cons: ['B 站 TV 签名密钥可能被换，到时这一档会失效', '失效会自动降级到标准模式，不会卡住'],
        note: '实验性档位。建议偶尔用，主用还是标准模式或极清模式。',
      },
      dashRemux: {
        displayName: '极清（ffmpeg 实时合流）',
        summary: '本机实时合流后推给电视。最高清，但本机必须一直开着。',
        pros: ['最高清晰度（1080P60 / 4K / HDR 都可以）', '覆盖最广，DASH-only 视频也能投'],
        cons: ['本机必须保持开机和运行，关掉立刻断流', '占用一些 CPU 和网络上行带宽', '需要 ffmpeg（已自动随 App 安装）'],
        note: '电视播放期间不要退出 BiliCast。',
      },
    };

    const $ = (id) => document.getElementById(id);
    const tokenInput = $('token');
    const tokenDisplay = $('token-display');
    const tokenInputRow = $('token-input-row');
    const pairing = $('pairing');
    const statusDot = $('status-dot');
    const statusText = $('status-text');
    const controlAddr = $('control-addr');
    const proxyAddr = $('proxy-addr');
    const ffmpegBadge = $('ffmpeg-badge');
    const qualitySelect = $('quality');
    const qualitySummary = $('quality-summary');
    const qualityProsCons = $('quality-pros-cons');
    const qualityNote = $('quality-note');
    const deviceCount = $('device-count');
    const devicesNode = $('devices');
    const sessionSection = $('session-section');
    const sessionTitle = $('session-title');
    const sessionMeta = $('session-meta');
    const sessionTier = $('session-tier');

    tokenInput.value = localStorage.getItem(TOKEN_KEY) || '';

    function token() { return tokenInput.value.trim(); }
    function headers(json = false) {
      const h = { 'Accept': 'application/json' };
      if (json) h['Content-Type'] = 'application/json';
      if (token()) h['X-BiliCast-Token'] = token();
      return h;
    }
    async function api(path, options = {}) {
      const url = path.startsWith('/api/') ? path : API_PREFIX + path;
      const res = await fetch(url, {
        method: options.method || 'GET',
        headers: headers(Boolean(options.body)),
        body: options.body ? JSON.stringify(options.body) : undefined,
      });
      const data = await res.json().catch(() => null);
      if (!res.ok || !data || !data.ok) {
        const msg = data && data.error ? data.error.message : ('HTTP ' + res.status);
        throw new Error(msg);
      }
      return data.data;
    }

    async function bootstrapToken() {
      if (token()) return;
      try {
        const res = await fetch(API_PREFIX + '/pairing/token');
        const json = await res.json();
        const value = json && json.ok && json.data ? json.data.token : '';
        if (value) {
          tokenInput.value = value;
          localStorage.setItem(TOKEN_KEY, value);
        }
      } catch (_) {}
    }

    function maskedToken() {
      const t = token();
      if (!t) return '(未设置)';
      if (t.length <= 10) return '•'.repeat(t.length);
      return t.slice(0, 4) + '••••••••' + t.slice(-4);
    }
    function renderToken() { tokenDisplay.textContent = maskedToken(); }

    async function checkPairing() {
      try {
        const res = await fetch(API_PREFIX + '/pairing/status', { headers: headers() });
        const json = await res.json();
        const paired = json.ok && json.data && json.data.paired;
        pairing.textContent = paired ? 'Token 有效' : 'Token 未验证';
        pairing.className = paired ? 'small ok' : 'small muted';
      } catch (e) {
        pairing.textContent = e.message || String(e);
        pairing.className = 'small err';
      }
    }
    function setStatus(state, text) {
      statusDot.className = 'status-dot' + (state ? ' ' + state : '');
      statusText.textContent = text;
    }
    async function refreshStatus() {
      try {
        const data = await api('/status');
        setStatus('running', '服务运行中');
        if (data.controlAddr) controlAddr.textContent = data.controlAddr;
        if (data.proxyAddr) proxyAddr.textContent = '代理：' + data.proxyAddr;
        renderQuality(data);
        renderSession(data.currentSession);
      } catch (e) {
        setStatus('failed', '服务异常');
      }
    }
    function renderQuality(data) {
      const opts = data.qualityPreferenceOptions || ['mp4Safe', 'flvTV', 'dashRemux'];
      qualitySelect.innerHTML = '';
      for (const value of opts) {
        const info = QUALITY_INFO[value];
        const option = document.createElement('option');
        option.value = value;
        option.textContent = info ? info.displayName : value;
        option.selected = value === data.qualityPreference;
        qualitySelect.appendChild(option);
      }
      ffmpegBadge.textContent = data.ffmpegAvailable ? 'ffmpeg 已内置' : 'ffmpeg 未装';
      ffmpegBadge.className = 'badge ' + (data.ffmpegAvailable ? 'ok' : 'warn');
      renderQualityCard(data.qualityPreference);
    }
    function renderQualityCard(preference) {
      const info = QUALITY_INFO[preference] || QUALITY_INFO.mp4Safe;
      qualitySummary.textContent = info.summary;
      qualityProsCons.innerHTML = '';
      for (const p of info.pros) {
        const div = document.createElement('div');
        div.className = 'pro';
        const span = document.createElement('span');
        span.textContent = p;
        div.appendChild(span);
        qualityProsCons.appendChild(div);
      }
      for (const c of info.cons) {
        const div = document.createElement('div');
        div.className = 'con';
        const span = document.createElement('span');
        span.textContent = c;
        div.appendChild(span);
        qualityProsCons.appendChild(div);
      }
      if (info.note) {
        qualityNote.textContent = info.note;
        qualityNote.style.display = '';
      } else {
        qualityNote.style.display = 'none';
      }
    }
    function renderSession(session) {
      if (!session) {
        sessionSection.style.display = 'none';
        return;
      }
      sessionSection.style.display = '';
      sessionTitle.textContent = session.title || 'BiliCast';
      const tierLabel = QUALITY_INFO[session.tier] ? QUALITY_INFO[session.tier].displayName : (session.tier || '');
      sessionTier.textContent = tierLabel;
      sessionMeta.textContent = '→ ' + (session.deviceName || '');
    }
    async function refreshDevices() {
      try {
        const data = await api('/devices');
        const devices = data.devices || [];
        deviceCount.textContent = '(' + devices.length + ')';
        devicesNode.innerHTML = '';
        if (devices.length === 0) {
          const div = document.createElement('div');
          div.className = 'empty';
          div.textContent = '尚未发现设备。请确认电视和电脑在同一 Wi-Fi，并打开电视的 DLNA / 投屏功能。';
          devicesNode.appendChild(div);
          return;
        }
        for (const d of devices) {
          const row = document.createElement('div');
          row.className = 'device-row';
          row.innerHTML = '<div class="device-icon">📺</div>' +
            '<div class="grow"><div class="device-name"></div><div class="device-sub"></div></div>';
          row.querySelector('.device-name').textContent = d.name || d.id;
          const bits = [d.manufacturer, d.modelName].filter(Boolean);
          row.querySelector('.device-sub').textContent = bits.join(' · ') || (d.location || '');
          devicesNode.appendChild(row);
        }
      } catch (e) {
        devicesNode.innerHTML = '';
        const err = document.createElement('div');
        err.className = 'empty err';
        err.textContent = e.message || String(e);
        devicesNode.appendChild(err);
      }
    }
    async function refreshAll() {
      renderToken();
      await checkPairing();
      await refreshStatus();
      await refreshDevices();
    }

    // Wire up events
    $('copy-token').addEventListener('click', async () => {
      const t = token();
      if (!t) { alert('当前没有 token'); return; }
      try {
        await navigator.clipboard.writeText(t);
        const btn = $('copy-token');
        const orig = btn.textContent;
        btn.textContent = '已复制';
        setTimeout(() => (btn.textContent = orig), 1200);
      } catch (e) { alert('复制失败：' + (e.message || e)); }
    });
    $('edit-token').addEventListener('click', () => {
      tokenInputRow.classList.add('show');
      tokenInput.type = 'text';
      tokenInput.focus();
    });
    $('cancel-token').addEventListener('click', () => {
      tokenInputRow.classList.remove('show');
      tokenInput.type = 'password';
      tokenInput.value = localStorage.getItem(TOKEN_KEY) || '';
    });
    $('save-token').addEventListener('click', async () => {
      localStorage.setItem(TOKEN_KEY, token());
      tokenInputRow.classList.remove('show');
      tokenInput.type = 'password';
      await refreshAll();
    });
    $('refresh-devices').addEventListener('click', async () => {
      const btn = $('refresh-devices');
      btn.disabled = true; btn.textContent = '扫描中…';
      try { await api('/devices/refresh', { method: 'POST', body: {} }); }
      catch (e) { /* refresh error is non-fatal */ }
      await refreshDevices();
      setTimeout(() => { btn.disabled = false; btn.textContent = '重新扫描'; }, 500);
    });
    qualitySelect.addEventListener('change', async () => {
      try {
        await api('/preferences', { method: 'PUT', body: { qualityPreference: qualitySelect.value } });
        await refreshStatus();
      } catch (e) { alert(e.message || String(e)); }
    });
    $('stop-cast').addEventListener('click', async () => {
      try {
        const status = await api('/status');
        const deviceId = status.currentSession && status.currentSession.deviceId;
        if (!deviceId) throw new Error('当前状态未返回 deviceId');
        await api('/cast/stop', { method: 'POST', body: { deviceId } });
        await refreshAll();
      } catch (e) { alert(e.message || String(e)); }
    });

    bootstrapToken().then(refreshAll);
    setInterval(refreshAll, 5000);
  </script>
</body>
</html>`
