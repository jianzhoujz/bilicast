package backend

import "net/http"

func (s *Service) handleConsole(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	_, _ = w.Write([]byte(consoleHTML))
}

const consoleHTML = `<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>BiliCastHelper Console</title>
  <style>
    :root { color-scheme: light dark; }
    body {
      margin: 0;
      color: #18191c;
      background: #f6f7f8;
      font: 14px/1.5 -apple-system, BlinkMacSystemFont, "Segoe UI", "PingFang SC", sans-serif;
    }
    main { max-width: 960px; margin: 32px auto; padding: 0 18px; }
    h1 { margin: 0 0 6px; font-size: 24px; }
    h2 { margin: 0 0 12px; font-size: 16px; }
    section {
      background: #fff;
      border: 1px solid #e3e5e7;
      border-radius: 14px;
      padding: 16px;
      margin: 14px 0;
      box-shadow: 0 8px 24px rgba(0,0,0,.04);
    }
    label { display: block; font-weight: 650; margin-bottom: 6px; }
    input, select {
      box-sizing: border-box;
      width: 100%;
      max-width: 520px;
      padding: 8px 10px;
      border: 1px solid #ccd0d7;
      border-radius: 8px;
      background: #fff;
      color: inherit;
      font: inherit;
    }
    button {
      border: 0;
      border-radius: 8px;
      background: #fb7299;
      color: #fff;
      padding: 8px 12px;
      cursor: pointer;
      font: inherit;
      font-weight: 650;
    }
    button.secondary { background: #6b7280; }
    button.danger { background: #d03050; }
    button:disabled { opacity: .55; cursor: not-allowed; }
    .row { display: flex; flex-wrap: wrap; gap: 8px; align-items: center; }
    .muted { color: #6b7280; }
    .ok { color: #168348; }
    .error { color: #d03050; }
    .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(220px, 1fr)); gap: 12px; }
    .card { border: 1px solid #e3e5e7; border-radius: 12px; padding: 12px; background: #fafafa; }
    pre { white-space: pre-wrap; overflow-wrap: anywhere; background: #f1f2f3; border-radius: 10px; padding: 12px; }
    @media (prefers-color-scheme: dark) {
      body { background: #111318; color: #f1f2f3; }
      section, .card { background: #181b22; border-color: #303642; }
      input, select { background: #111318; border-color: #303642; }
      pre { background: #111318; }
      .muted { color: #a5adba; }
    }
  </style>
</head>
<body>
  <main>
    <h1>BiliCastHelper Console</h1>
    <div class="muted">Docker / daemon 后台控制页。控制 API 建议只绑定宿主机 localhost。</div>

    <section>
      <h2>配对 Token</h2>
      <label for="token">X-BiliCast-Token</label>
      <div class="row">
        <input id="token" type="password" autocomplete="off" placeholder="粘贴 bilicastd 输出或 config.json 里的 token">
        <button id="save-token">保存</button>
        <button id="clear-token" class="secondary">清除</button>
      </div>
      <p id="pairing" class="muted">未检查</p>
    </section>

    <section>
      <h2>服务状态</h2>
      <div class="row">
        <button id="refresh">刷新状态</button>
      </div>
      <pre id="status">等待刷新…</pre>
    </section>

    <section>
      <h2>清晰度</h2>
      <div class="row">
        <select id="quality"></select>
        <button id="save-quality">保存清晰度</button>
      </div>
      <p id="quality-note" class="muted"></p>
    </section>

    <section>
      <h2>DLNA 设备</h2>
      <div class="row">
        <button id="refresh-devices">刷新设备</button>
      </div>
      <div id="devices" class="grid"></div>
    </section>

    <section>
      <h2>当前投屏</h2>
      <div id="session" class="muted">暂无会话</div>
    </section>
  </main>

  <script>
    const TOKEN_KEY = 'bilicast.token';
    const tokenInput = document.getElementById('token');
    const pairing = document.getElementById('pairing');
    const statusNode = document.getElementById('status');
    const qualitySelect = document.getElementById('quality');
    const qualityNote = document.getElementById('quality-note');
    const devicesNode = document.getElementById('devices');
    const sessionNode = document.getElementById('session');

    tokenInput.value = localStorage.getItem(TOKEN_KEY) || '';

    async function bootstrapToken() {
      if (token()) return;
      try {
        const res = await fetch('/api/bilicast/pairing/token');
        const json = await res.json();
        const value = json && json.ok && json.data ? json.data.token : '';
        if (value) {
          tokenInput.value = value;
          localStorage.setItem(TOKEN_KEY, value);
        }
      } catch (_) {}
    }

    function token() { return tokenInput.value.trim(); }
    function headers(json = false) {
      const h = { 'Accept': 'application/json' };
      if (json) h['Content-Type'] = 'application/json';
      if (token()) h['X-BiliCast-Token'] = token();
      return h;
    }
    const API_PREFIX = '/api/bilicast';

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
    function renderError(node, error) {
      node.textContent = error && error.message ? error.message : String(error);
      node.className = 'error';
    }
    async function checkPairing() {
      try {
        const res = await fetch(API_PREFIX + '/pairing/status', { headers: headers() });
        const json = await res.json();
        pairing.textContent = json.ok && json.data && json.data.paired ? 'Token 有效' : 'Token 未验证';
        pairing.className = json.ok && json.data && json.data.paired ? 'ok' : 'muted';
      } catch (e) { renderError(pairing, e); }
    }
    async function refreshStatus() {
      try {
        const data = await api('/status');
        statusNode.textContent = JSON.stringify(data, null, 2);
        statusNode.className = '';
        renderSession(data.currentSession);
        await refreshPreferences();
      } catch (e) { renderError(statusNode, e); }
    }
    function renderSession(session) {
      if (!session) {
        sessionNode.textContent = '暂无会话';
        sessionNode.className = 'muted';
        return;
      }
      sessionNode.className = '';
      sessionNode.innerHTML = '';
      const card = document.createElement('div');
      card.className = 'card';
      card.innerHTML = '<strong>' + escapeHTML(session.title || 'BiliCast') + '</strong><br>' +
        '设备：' + escapeHTML(session.deviceName || '') + '<br>' +
        '清晰度：' + escapeHTML(session.tier || '') + '<br>' +
        '开始：' + escapeHTML(session.startedAt || '');
      if (session.deviceName) {
        const stop = document.createElement('button');
        stop.className = 'danger';
        stop.textContent = '停止投屏';
        stop.addEventListener('click', async () => {
          try {
            const status = await api('/status');
            const deviceId = status.currentSession && status.currentSession.deviceId;
            if (!deviceId) throw new Error('当前状态未返回 deviceId');
            await api('/cast/stop', { method: 'POST', body: { deviceId } });
            await refreshAll();
          } catch (e) { alert(e.message || String(e)); }
        });
        card.appendChild(document.createElement('br'));
        card.appendChild(stop);
      }
      sessionNode.appendChild(card);
    }
    async function refreshPreferences() {
      try {
        const data = await api('/preferences');
        qualitySelect.innerHTML = '';
        for (const value of data.qualityPreferenceOptions || []) {
          const option = document.createElement('option');
          option.value = value;
          option.textContent = value;
          option.selected = value === data.qualityPreference;
          qualitySelect.appendChild(option);
        }
        qualityNote.textContent = data.ffmpegAvailable ? 'ffmpeg 可用' : 'ffmpeg 不可用，dashRemux 会自动跳过';
      } catch (e) { renderError(qualityNote, e); }
    }
    async function refreshDevices() {
      try {
        const data = await api('/devices');
        devicesNode.innerHTML = '';
        const devices = data.devices || [];
        if (devices.length === 0) {
          devicesNode.innerHTML = '<p class="muted">暂无设备。Docker 部署可用 BILICAST_DEVICES_JSON 注入设备。</p>';
          return;
        }
        for (const d of devices) {
          const card = document.createElement('div');
          card.className = 'card';
          card.innerHTML = '<strong>' + escapeHTML(d.name || d.id) + '</strong><br>' +
            'ID：' + escapeHTML(d.id || '') + '<br>' +
            '型号：' + escapeHTML(d.modelName || '-') + '<br>' +
            '厂商：' + escapeHTML(d.manufacturer || '-') + '<br>' +
            '状态：' + (d.available ? '可用' : '不可用');
          devicesNode.appendChild(card);
        }
      } catch (e) {
        devicesNode.innerHTML = '<p class="error">' + escapeHTML(e.message || String(e)) + '</p>';
      }
    }
    async function refreshAll() {
      await checkPairing();
      await refreshStatus();
      await refreshDevices();
    }
    function escapeHTML(value) {
      return String(value == null ? '' : value).replace(/[&<>'"]/g, ch => ({'&':'&amp;','<':'&lt;','>':'&gt;',"'":'&#39;','"':'&quot;'}[ch]));
    }

    document.getElementById('save-token').addEventListener('click', async () => {
      localStorage.setItem(TOKEN_KEY, token());
      await refreshAll();
    });
    document.getElementById('clear-token').addEventListener('click', () => {
      localStorage.removeItem(TOKEN_KEY);
      tokenInput.value = '';
      pairing.textContent = '已清除';
      pairing.className = 'muted';
    });
    document.getElementById('refresh').addEventListener('click', refreshAll);
    document.getElementById('refresh-devices').addEventListener('click', async () => {
      try { await api('/devices/refresh', { method: 'POST', body: {} }); } catch (e) { alert(e.message || String(e)); }
      await refreshDevices();
    });
    document.getElementById('save-quality').addEventListener('click', async () => {
      try {
        await api('/preferences', { method: 'PUT', body: { qualityPreference: qualitySelect.value } });
        await refreshAll();
      } catch (e) { alert(e.message || String(e)); }
    });

    bootstrapToken().then(refreshAll);
  </script>
</body>
</html>`
