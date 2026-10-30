const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { parseCode, appURL } = require('../../docs/join/join.js');
const code = '0123456789abcdef0123456789abcdef';
test('HTTPS fragment and old app links preserve the code', () => {
  for (const value of [
    code, code.toUpperCase(),
    `https://tihshkel.github.io/Mono-Task/join/#${code}`,
    `https://egoar777.github.io/MonoTask/join/#${code}`,
    `com.monotask.ios://join?code=${code}`
  ]) assert.equal(parseCode(value), code);
  assert.equal(appURL(code), `com.monotask.ios://join?code=${code}`);
});

const joinDirectory = path.resolve(__dirname, '../../docs/join');
const script = fs.readFileSync(path.join(joinDirectory, 'join.js'), 'utf8');

function loadPage(hash, clipboardWorks = true) {
  const elements = Object.fromEntries([
    'open', 'copy', 'status', 'manual', 'code', 'copy-label', 'invitation', 'folder-peek'
  ].map(id => {
    const classes = new Set();
    return [id, {
      attributes: {}, listeners: {}, dataset: {}, hidden: id === 'manual', value: '',
      setAttribute(name, value) { this.attributes[name] = value; },
      removeAttribute(name) { delete this.attributes[name]; if (name === 'href') delete this.href; },
      addEventListener(name, handler) { this.listeners[name] = handler; },
      focus() { this.focused = true; },
      select() { this.selected = true; },
      classList: { toggle(name) { if (classes.has(name)) { classes.delete(name); return false; } classes.add(name); return true; } }
    }];
  }));
  const events = {};
  const copied = [];
  const location = { hash };
  vm.runInNewContext(script, {
    URL,
    document: { getElementById(id) { assert.ok(elements[id], id); return elements[id]; } },
    window: { location, addEventListener(name, handler) { events[name] = handler; } },
    navigator: { clipboard: { async writeText(value) { if (!clipboardWorks) throw new Error('Clipboard unavailable'); copied.push(value); } } }
  });
  return { elements, events, location, copied };
}

test('a valid fragment enables explicit app opening and copying', async () => {
  const { elements, copied } = loadPage(`#${code}`);
  assert.equal(elements.open.href, `com.monotask.ios://join?code=${code}`);
  assert.equal(elements.open.attributes['aria-disabled'], 'false');
  assert.equal(elements.copy.disabled, false);
  assert.equal(elements.manual.hidden, true);
  assert.equal(elements.invitation.dataset.state, 'ready');
  assert.equal(elements.status.textContent, 'Нажмите «Открыть в MonoTask» — подключим папку и сразу покажем задачи.');
  await elements.copy.listeners.click();
  assert.deepEqual(copied, [code]);
  assert.equal(elements['copy-label'].textContent, 'Код скопирован');
});

test('missing and malformed codes offer manual entry without an app link', () => {
  const { elements, events, location } = loadPage('');
  assert.equal(elements.invitation.dataset.state, 'missing');
  assert.equal(elements.manual.hidden, false);
  assert.equal(elements.copy.disabled, true);
  assert.equal(elements.open.href, undefined);
  elements.code.value = `https://tihshkel.github.io/Mono-Task/join/#${code}`;
  elements.code.listeners.input();
  assert.equal(elements.invitation.dataset.state, 'ready');
  location.hash = '#invalid';
  events.hashchange();
  assert.equal(elements.invitation.dataset.state, 'invalid');
  assert.equal(elements.open.href, undefined);
  assert.equal(elements.copy.disabled, true);
  let prevented = false;
  elements.open.listeners.click({ preventDefault() { prevented = true; } });
  assert.equal(prevented, true);
});

test('clipboard failure exposes a selected code and the folder opens by click', async () => {
  const { elements } = loadPage(`#${code}`, false);
  await elements.copy.listeners.click();
  assert.equal(elements.manual.hidden, false);
  assert.equal(elements.code.value, code);
  assert.equal(elements.code.readOnly, true);
  assert.equal(elements.code.focused, true);
  assert.equal(elements.code.selected, true);
  const folder = elements['folder-peek'];
  folder.listeners.click();
  assert.equal(folder.attributes['aria-pressed'], 'true');
  folder.listeners.click();
  assert.equal(folder.attributes['aria-pressed'], 'false');
});

test('chat metadata references a real 1200 by 630 cover and current app logos', () => {
  const html = fs.readFileSync(path.join(joinDirectory, 'index.html'), 'utf8');
  const imageURL = /property="og:image" content="([^"]+)"/.exec(html)[1];
  assert.equal(imageURL, 'https://tihshkel.github.io/Mono-Task/join/assets/invitation-v2.png');
  assert.ok(html.includes('name="twitter:card" content="summary_large_image"'));
  assert.ok(html.includes('property="og:site_name" content="MonoTask"'));
  assert.ok(html.includes('name="twitter:image" content="' + imageURL + '"'));
  assert.ok(!html.includes('raw.githubusercontent.com'));
  const cover = fs.readFileSync(path.join(joinDirectory, 'assets/invitation-v2.png'));
  assert.equal(cover.readUInt32BE(16), 1200);
  assert.equal(cover.readUInt32BE(20), 630);
  for (const appearance of ['light', 'dark']) {
    assert.deepEqual(
      fs.readFileSync(path.join(joinDirectory, `assets/logo-${appearance}-v2.png`)),
      fs.readFileSync(path.resolve(__dirname, `../../MonoTask/Resources/Assets.xcassets/BrandLogo.imageset/logo-${appearance}@2x.png`))
    );
  }
});
test('untrusted URLs and malformed codes cannot launch the app', () => {
  for (const value of ['', 'short', 'g'.repeat(32), `https://evil.test/Mono-Task/join/#${code}`, `https://tihshkel.github.io@evil.test/Mono-Task/join/#${code}`, `http://tihshkel.github.io/Mono-Task/join/#${code}`, `https://tihshkel.github.io/Mono-Task/join/?code=${code}`, `https://tihshkel.github.io/MonoTask/join/#${code}`, `https://tihshkel.github.io/wrong/#${code}`, `https://egoar777.github.io@evil.test/MonoTask/join/#${code}`, `http://egoar777.github.io/MonoTask/join/#${code}`, `https://egoar777.github.io/Mono-Task/join/#${code}`, 'javascript:alert(1)', `<script>${code}</script>`]) {
    assert.equal(parseCode(value), null, value);
    assert.equal(appURL(value), null, value);
  }
});
