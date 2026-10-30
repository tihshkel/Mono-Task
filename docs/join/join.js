(function () {
  'use strict';
  function parseCode(input) {
    let value = input.trim();
    if (!/^[0-9a-f]{32}$/i.test(value)) {
      try {
        const url = new URL(value);
        if (url.username || url.password || url.port) return null;
        const pages = {
          'tihshkel.github.io': '/Mono-Task/join/',
          'egoar777.github.io': '/MonoTask/join/'
        };
        if (url.protocol === 'https:' && pages[url.hostname] === url.pathname && !url.search) value = url.hash.slice(1);
        else if (url.protocol === 'com.monotask.ios:' && url.hostname === 'join') value = url.searchParams.get('code') || '';
        else return null;
      } catch { return null; }
    }
    return /^[0-9a-f]{32}$/i.test(value) ? value.toLowerCase() : null;
  }
  function appURL(code) {
    const valid = parseCode(code);
    return valid ? 'com.monotask.ios://join?code=' + valid : null;
  }
  if (typeof module !== 'undefined' && module.exports) { module.exports = { parseCode, appURL }; return; }
  const open = document.getElementById('open');
  const copy = document.getElementById('copy');
  const status = document.getElementById('status');
  const manual = document.getElementById('manual');
  const input = document.getElementById('code');
  const copyLabel = document.getElementById('copy-label');
  const invitation = document.getElementById('invitation');
  const folder = document.getElementById('folder-peek');
  let code;
  function update(value) {
    code = parseCode(value);
    open.setAttribute('aria-disabled', String(!code));
    copy.disabled = !code;
    copyLabel.textContent = 'Скопировать код';
    input.readOnly = false;
    if (code) {
      open.href = appURL(code);
      invitation.dataset.state = 'ready';
      status.textContent = 'Нажмите «Открыть в MonoTask» — подключим папку и сразу покажем задачи.';
    } else {
      open.removeAttribute('href');
      manual.hidden = false;
      invitation.dataset.state = value.trim() ? 'invalid' : 'missing';
      status.textContent = value.trim()
        ? 'Не удалось прочитать код. Вставьте приглашение ниже или попросите отправить новую ссылку.'
        : 'У вас есть приглашение? Вставьте ссылку или код ниже.';
    }
  }
  update(window.location.hash.slice(1));
  window.addEventListener('hashchange', () => update(window.location.hash.slice(1)));
  input.addEventListener('input', () => update(input.value));
  open.addEventListener('click', (event) => {
    if (!code) { event.preventDefault(); return; }
    status.textContent = 'Подтвердите открытие MonoTask. Если ничего не произошло, используйте код приглашения.';
  });
  copy.addEventListener('click', async () => {
    if (!code) return;
    try {
      await navigator.clipboard.writeText(code);
      copyLabel.textContent = 'Код скопирован';
      status.textContent = 'Код скопирован. В MonoTask: Общие списки → Присоединиться.';
    } catch {
      manual.hidden = false;
      input.value = code;
      input.readOnly = true;
      input.focus();
      input.select();
      status.textContent = 'Выделенный код можно скопировать вручную.';
    }
  });
  folder.addEventListener('click', () => {
    const expanded = folder.classList.toggle('is-open');
    folder.setAttribute('aria-pressed', String(expanded));
  });
}());
