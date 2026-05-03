const TOKEN_KEY = 'bilicast.token';
const LOCAL_API = 'http://127.0.0.1:18787';

const tokenInput = document.getElementById('token');
const statusNode = document.getElementById('status');
const healthNode = document.getElementById('health');

function setStatus(message) {
  statusNode.textContent = message || '';
}

async function checkHealth() {
  try {
    const res = await fetch(LOCAL_API + '/api/health', { credentials: 'omit' });
    const json = await res.json().catch(() => null);
    healthNode.textContent = res.ok && json && json.ok
      ? `本地服务已连接：${json.data?.app || 'BiliCast'} ${json.data?.version || ''}`.trim()
      : '本地服务响应异常，请确认菜单栏 App 状态。';
  } catch (_) {
    healthNode.textContent = '未检测到本地服务，请先启动 BiliCast 菜单栏 App。';
  }
}

chrome.storage.local.get({ [TOKEN_KEY]: '' }, (items) => {
  tokenInput.value = items[TOKEN_KEY] || '';
});

checkHealth();

document.getElementById('save').addEventListener('click', () => {
  const token = tokenInput.value.trim();
  chrome.storage.local.set({ [TOKEN_KEY]: token }, () => setStatus('Token 已保存。'));
});

document.getElementById('clear').addEventListener('click', () => {
  tokenInput.value = '';
  chrome.storage.local.set({ [TOKEN_KEY]: '' }, () => setStatus('Token 已清除。'));
});
