const REQUEST_TIMEOUT_FALLBACK_MS = 8000;

function withTimeout(ms) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), ms || REQUEST_TIMEOUT_FALLBACK_MS);
  return { controller, done: () => clearTimeout(timer) };
}

async function handleRequest(request) {
  const timeout = withTimeout(request.timeout || REQUEST_TIMEOUT_FALLBACK_MS);
  try {
    const response = await fetch(request.url, {
      method: request.method || 'GET',
      headers: request.headers || {},
      body: request.data,
      signal: timeout.controller.signal,
      credentials: 'omit',
    });
    const text = await response.text();
    return {
      ok: response.status >= 200 && response.status < 300,
      status: response.status,
      body: text,
      text,
    };
  } catch (error) {
    return {
      ok: false,
      status: 0,
      error: error && error.name === 'AbortError' ? 'timeout' : 'network',
    };
  } finally {
    timeout.done();
  }
}

function storageGet(key) {
  return new Promise((resolve) => {
    chrome.storage.local.get({ [key]: '' }, (items) => {
      resolve({ ok: true, value: items[key] || '' });
    });
  });
}

function storageSet(key, value) {
  return new Promise((resolve) => {
    chrome.storage.local.set({ [key]: value || '' }, () => {
      resolve({ ok: true });
    });
  });
}

chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
  if (!message || typeof message.type !== 'string') return false;

  if (message.type === 'bilicast.request') {
    handleRequest(message.request || {}).then(sendResponse);
    return true;
  }

  if (message.type === 'bilicast.storage.get') {
    storageGet(message.key).then(sendResponse);
    return true;
  }

  if (message.type === 'bilicast.storage.set') {
    storageSet(message.key, message.value).then(sendResponse);
    return true;
  }

  return false;
});
