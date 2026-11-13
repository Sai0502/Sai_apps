import fs from 'node:fs';
import vm from 'node:vm';
import path from 'node:path';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';

const root = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const source = fs.readFileSync(path.join(root, 'hotkey-hook.js'), 'utf8');
const CONFIG_TYPE = 'tradovate-auto-lock:hotkey-config';
const DEBUG_REQUEST_TYPE = 'tradovate-auto-lock:hotkey-debug-request';
const DEBUG_RESPONSE_TYPE = 'tradovate-auto-lock:hotkey-debug-response';

const clicks = [];
const logs = [];
const pageHandled = [];
const listeners = { window: {}, document: {} };
let pageHotkeyEnabled = true;

function makeEl(text, width, height, attrs = {}) {
  return {
    tagName: 'BUTTON',
    id: '',
    className: '',
    disabled: false,
    innerText: text,
    textContent: text,
    offsetParent: {},
    offsetWidth: width,
    offsetHeight: height,
    getClientRects() { return [{}]; },
    getBoundingClientRect() { return { left: 0, top: 0, width, height }; },
    getAttribute(name) { return attrs[name] || null; },
    click() { clicks.push(text); }
  };
}

const els = [
  makeEl('市价买入', 300, 60),
  makeEl('市价卖出', 300, 60),
  makeEl('市价退仓并撤销', 300, 60),
  makeEl('Buy', 120, 40),
  makeEl('Sell', 120, 40)
];

class FakeKeyboardEvent {
  constructor(type, init) {
    Object.assign(this, init || {});
    this.type = type;
    this.defaultPrevented = false;
    this.__tdvHotkeySynthetic = false;
  }
  preventDefault() { this.defaultPrevented = true; }
  stopPropagation() {}
  stopImmediatePropagation() {}
}

function on(target, type, fn) {
  (listeners[target][type] ||= []).push(fn);
}

function emitMessage(data) {
  for (const fn of [...(listeners.window.message || [])]) fn({ data });
}

const window = {
  addEventListener(type, fn) { on('window', type, fn); },
  dispatchEvent() { return true; },
  postMessage(data) { emitMessage(data); }
};
window.top = window;
window.self = window;
window.window = window;

const document = {
  addEventListener(type, fn) { on('document', type, fn); },
  querySelectorAll() { return els; }
};
document.documentElement = {};
document.body = {
  dispatchEvent(event) {
    for (const fn of [...(listeners.document.keydown || [])]) fn(event);
    return !event.defaultPrevented;
  }
};

const context = vm.createContext({
  window,
  document,
  location: { href: 'https://trader.tradovate.com/' },
  console: { log: (...args) => logs.push(args.join(' ')) },
  setTimeout() {},
  KeyboardEvent: FakeKeyboardEvent
});
window.console = context.console;

vm.runInContext(source, context, { filename: 'hotkey-hook.js' });

// 模拟 Tradovate 4760.js 里的 Hotkeys.keydown：只认 Ctrl/Cmd/Alt + Digit1-3
function pageHotkey(event) {
  if (!pageHotkeyEnabled) return;
  if (!event.key || event.key.length !== 1) return;
  const code = event.code || '';
  if (code.indexOf('Key') === -1 && code.indexOf('Digit') === -1) return;
  let combo = '';
  if (event.ctrlKey) combo += 'Ctrl+';
  if (event.metaKey) combo += 'Command+';
  if (event.altKey) combo += 'Alt+';
  if (event.shiftKey) combo += 'Shift+';
  combo += code;
  if (combo === 'Ctrl+Command+Alt+Digit1' ||
      combo === 'Ctrl+Command+Alt+Digit2' ||
      combo === 'Ctrl+Command+Alt+Digit3') {
    pageHandled.push(combo);
    event.preventDefault();
    event.stopPropagation();
  }
}
on('document', 'keydown', pageHotkey);

function fireConfig(map) {
  emitMessage({ source: CONFIG_TYPE, map });
}

function press(key, code, extra = {}) {
  let prevented = false;
  const event = {
    key,
    code,
    ctrlKey: false,
    metaKey: false,
    altKey: false,
    shiftKey: false,
    preventDefault() { prevented = true; },
    stopImmediatePropagation() {},
    stopPropagation() {},
    ...extra
  };
  for (const fn of [...(listeners.window.keydown || [])]) fn(event);
  return { prevented, last: window.__tdvHotkeyLast };
}

fireConfig({
  buy: { from: 'Ctrl+Command+Alt+E', to: 'W' },
  sell: { from: 'Ctrl+Command+Alt+2', to: 'S' },
  close: { from: 'Ctrl+Command+Alt+3', to: 'Space' }
});

assert.equal(window.__tdvHotkeyMap.buy.to, 'W', 'config delivered to MAIN world');
assert.equal(window.__tdvHotkeyMap.close.to, 'Space', 'space mapping delivered');

clicks.length = 0;
let result = press('w', 'KeyW');
assert.equal(result.prevented, true, 'W is intercepted');
assert.equal(result.last.matched, true, 'W matched');
assert.equal(result.last.action, 'buy', 'W maps to buy');
assert.equal(result.last.nativeHandled, true, 'W dispatches native Ctrl+Command+Alt+1');
assert.equal(result.last.clicked, false, 'native path avoids clicking the button');
assert.equal(clicks.length, 0, 'no fallback click when native hotkey is handled');

result = press('s', 'KeyS');
assert.equal(result.last.action, 'sell', 'S maps to sell');
assert.equal(result.last.nativeHandled, true, 'S dispatches native Ctrl+Command+Alt+2');

result = press(' ', 'Space');
assert.equal(result.last.action, 'close', 'Space maps to close');
assert.equal(result.last.nativeHandled, true, 'Space dispatches native Ctrl+Command+Alt+3');

result = press('1', 'Digit1', { ctrlKey: true, metaKey: true, altKey: true });
assert.equal(result.prevented, false, 'native Ctrl+Opt+Cmd+1 is not swallowed by the hook');

assert.deepEqual(pageHandled.slice(0, 3), [
  'Ctrl+Command+Alt+Digit1',
  'Ctrl+Command+Alt+Digit2',
  'Ctrl+Command+Alt+Digit3'
], 'Tradovate receives all three native chords');

pageHotkeyEnabled = false;
fireConfig({
  buy: { from: 'Ctrl+Command+Alt+1', to: 'B' },
  sell: { from: 'Ctrl+Command+Alt+2', to: 'S' },
  close: { from: 'Ctrl+Command+Alt+3', to: 'C' }
});

clicks.length = 0;
result = press('b', 'KeyB');
assert.equal(result.last.nativeHandled, false, 'fallback used when the page ignores the native chord');
assert.equal(result.last.clicked, true, 'fallback clicks a matching buy button');
assert.ok(clicks.includes('市价买入'), 'Chinese 市价买入 label is matched');

clicks.length = 0;
result = press('c', 'KeyC');
assert.equal(result.last.clicked, true, 'fallback clicks a matching close button');
assert.ok(clicks.includes('市价退仓并撤销'), 'Chinese 市价退仓并撤销 label is matched');

let debugResponse = null;
const debugHandler = event => {
  if (event.data && event.data.source === DEBUG_RESPONSE_TYPE) debugResponse = event.data;
};
on('window', 'message', debugHandler);
window.postMessage({ source: DEBUG_REQUEST_TYPE, requestId: 'test-1' });
assert.ok(debugResponse, 'debug request returns a response');
assert.equal(debugResponse.ok, true, 'debug response ok');
assert.equal(debugResponse.requestId, 'test-1', 'debug response carries requestId');
assert.equal(debugResponse.map.buy.to, 'B', 'debug response includes effective map');
assert.ok(Array.isArray(debugResponse.logs) && debugResponse.logs.length > 0, 'debug response includes logs');
assert.ok(Array.isArray(debugResponse.buttons) && debugResponse.buttons.length > 0, 'debug response includes button candidates');
assert.equal(debugResponse.actionButtons.buy.text, '市价买入', 'debug response includes resolved action buttons');

console.log('hotkey mapping tests passed');
console.log('hook build:', debugResponse.hookBuild);
console.log('page handled chords:', pageHandled.join(', '));
