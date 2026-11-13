// TradingAutoLock hotkey-hook.js (MAIN world, document_start)
// 在页面脚本之前注入，最早捕获 keydown。用户配置"原快捷键 -> 新快捷键"映射，
// 按下新快捷键时拦截并合成派发原快捷键事件，让 Tradovate 执行对应下单动作。
(function () {
  const HOOK_FLAG = '__tradingAutoLockHotkeyHookInstalled';
  const CONFIG_TYPE = 'tradovate-auto-lock:hotkey-config';
  const DEBUG_REQUEST_TYPE = 'tradovate-auto-lock:hotkey-debug-request';
  const DEBUG_RESPONSE_TYPE = 'tradovate-auto-lock:hotkey-debug-response';
  const HOOK_BUILD = 'v1111_1134';
  if (window[HOOK_FLAG]) return;
  window[HOOK_FLAG] = true;

  // world 自检：MAIN world 注入时扩展 API（chrome.runtime）不可见，ISOLATED 可见
  const IS_ISOLATED = (typeof chrome !== 'undefined' && !!chrome.runtime);
  console.log('[TradingAutoLock hotkey] injected platform=tdv',
    'url=' + location.href,
    'frame=' + (window.top === window.self ? 'top' : 'iframe'),
    'world=' + (IS_ISOLATED ? 'ISOLATED' : 'MAIN'));

  // 默认映射：buy/sell/close 三个动作
  const DEFAULT_MAP = {
    buy: { from: 'Ctrl+Command+Alt+1', to: '' },
    sell: { from: 'Ctrl+Command+Alt+2', to: '' },
    close: { from: 'Ctrl+Command+Alt+3', to: '' }
  };

  let hotkeyMap = DEFAULT_MAP;
  window.__tdvHotkeyMap = hotkeyMap;

  // ---- 诊断缓冲（只留在内存，由 content.js 按需拉取）----

  const hotkeyLogs = [];
  const mainWorldErrors = [];
  let configReceivedAt = null;

  function truncateText(value, max) {
    const text = String(value == null ? '' : value);
    return text.length > max ? text.slice(0, max) + '…' : text;
  }

  function hotkeyLog(event, details = {}) {
    try {
      hotkeyLogs.push({
        at: Date.now(),
        time: new Date().toISOString(),
        event,
        details
      });
      while (hotkeyLogs.length > 200) hotkeyLogs.shift();
    } catch (_) {
    }
  }

  function recordMainWorldError(kind, details) {
    try {
      mainWorldErrors.push({
        at: Date.now(),
        time: new Date().toISOString(),
        kind,
        details
      });
      while (mainWorldErrors.length > 60) mainWorldErrors.shift();
    } catch (_) {
    }
  }

  window.addEventListener('error', function (event) {
    recordMainWorldError('error', {
      message: event.message || '',
      source: event.filename || '',
      lineno: event.lineno || 0,
      colno: event.colno || 0,
      stack: truncateText(event.error && event.error.stack ? event.error.stack : '', 4000)
    });
  }, true);

  window.addEventListener('unhandledrejection', function (event) {
    const reason = event.reason;
    recordMainWorldError('unhandledrejection', {
      message: reason && reason.message ? reason.message : String(reason || ''),
      stack: truncateText(reason && reason.stack ? reason.stack : '', 4000)
    });
  }, true);

  hotkeyLog('injected', {
    build: HOOK_BUILD,
    url: location.href,
    frame: window.top === window.self ? 'top' : 'iframe',
    readyState: document.readyState || ''
  });

  // ---- 按键文本格式化 / 解析 ----

  const SPECIAL_KEYS = {
    ' ': 'Space',
    space: 'Space',
    spacebar: 'Space',
    enter: 'Enter',
    return: 'Enter',
    tab: 'Tab',
    escape: 'Escape',
    esc: 'Escape',
    backspace: 'Backspace',
    delete: 'Delete',
    del: 'Delete',
    arrowup: 'ArrowUp',
    arrowdown: 'ArrowDown',
    arrowleft: 'ArrowLeft',
    arrowright: 'ArrowRight',
    up: 'ArrowUp',
    down: 'ArrowDown',
    left: 'ArrowLeft',
    right: 'ArrowRight',
    home: 'Home',
    end: 'End',
    pageup: 'PageUp',
    pagedown: 'PageDown',
    insert: 'Insert',
    f1: 'F1', f2: 'F2', f3: 'F3', f4: 'F4', f5: 'F5', f6: 'F6',
    f7: 'F7', f8: 'F8', f9: 'F9', f10: 'F10', f11: 'F11', f12: 'F12'
  };

  // 用 e.code 识别按键名（不受键盘布局/输入法影响，如空格恒为 Space）
  function codeNameFromEvent(e) {
    const c = e.code || '';
    const lower = String(c).toLowerCase();
    if (lower === 'space') return 'Space';
    if (lower === 'enter') return 'Enter';
    if (lower === 'tab') return 'Tab';
    if (lower === 'escape') return 'Escape';
    if (lower === 'backspace') return 'Backspace';
    if (lower === 'delete') return 'Delete';
    if (lower === 'home') return 'Home';
    if (lower === 'end') return 'End';
    if (lower === 'pageup') return 'PageUp';
    if (lower === 'pagedown') return 'PageDown';
    if (lower === 'insert') return 'Insert';
    if (/^digit([0-9])$/.test(lower)) return lower.slice(5); // Digit3 -> 3
    if (/^key([a-z])$/.test(lower)) return lower.slice(3).toUpperCase(); // KeyW -> W
    if (/^f([1-9]|1[0-2])$/.test(lower)) return lower.toUpperCase(); // F1..F12
    if (/^arrow/.test(lower)) {
      const m = { arrowup: 'ArrowUp', arrowdown: 'ArrowDown', arrowleft: 'ArrowLeft', arrowright: 'ArrowRight' };
      return m[lower] || c;
    }
    return null;
  }

  function keyNameFromEvent(e) {
    // 优先用 e.code：不受键盘布局/输入法/Option 组合字符影响（Option+1 仍是 Digit1）
    const fromCode = codeNameFromEvent(e);
    if (fromCode) return fromCode;
    const k = e.key;
    if (!k || k === 'Dead' || k === 'Unidentified' || k === 'Process') return null;
    const lower = String(k).toLowerCase();
    if (lower === 'control' || lower === 'meta' || lower === 'alt' || lower === 'shift') return null; // 纯修饰键不算
    const mapped = SPECIAL_KEYS[lower];
    if (mapped) return mapped; // 空格/回车/方向键等特殊键优先统一命名（如 ' ' -> 'Space'）
    if (k.length === 1) return /[0-9]/.test(k) ? k : k.toUpperCase();
    return k;
  }

  function formatChord(e) {
    const parts = [];
    if (e.ctrlKey) parts.push('Ctrl');
    if (e.metaKey) parts.push('Command');
    if (e.altKey) parts.push('Alt');
    if (e.shiftKey) parts.push('Shift');
    const key = keyNameFromEvent(e);
    if (!key) return null;
    parts.push(key);
    return parts.join('+');
  }

  function parseChord(str) {
    const parts = String(str || '').split('+').map(s => s.trim()).filter(Boolean);
    const result = { ctrlKey: false, metaKey: false, altKey: false, shiftKey: false, key: '', code: '', keyCode: 0 };
    const keys = [];
    for (const p of parts) {
      const lower = p.toLowerCase();
      if (lower === 'ctrl' || lower === 'control') result.ctrlKey = true;
      else if (lower === 'cmd' || lower === 'command' || lower === 'meta') result.metaKey = true;
      else if (lower === 'alt' || lower === 'option') result.altKey = true;
      else if (lower === 'shift') result.shiftKey = true;
      else keys.push(p);
    }
    if (!keys.length) return null;
    const raw = keys.join('+');
    const lower = raw.toLowerCase();
    if (SPECIAL_KEYS[lower]) {
      result.key = SPECIAL_KEYS[lower];
    } else if (raw.length === 1) {
      result.key = /[0-9]/.test(raw) ? raw : raw.toUpperCase();
    } else {
      result.key = raw;
    }
    // 推导 code / keyCode
    const key = result.key;
    if (/^[0-9]$/.test(key)) { result.code = 'Digit' + key; result.keyCode = 48 + Number(key); }
    else if (/^[A-Z]$/.test(key)) { result.code = 'Key' + key; result.keyCode = 65 + key.charCodeAt(0) - 65; }
    else if (/^F([1-9]|1[0-2])$/.test(key)) { result.code = key; result.keyCode = 111 + Number(key.slice(1)); }
    else if (key === 'Space') { result.code = 'Space'; result.keyCode = 32; }
    else if (key === 'Enter') { result.code = 'Enter'; result.keyCode = 13; }
    else if (key === 'Tab') { result.code = 'Tab'; result.keyCode = 9; }
    else if (key === 'Escape') { result.code = 'Escape'; result.keyCode = 27; }
    else if (key === 'Backspace') { result.code = 'Backspace'; result.keyCode = 8; }
    else if (key === 'Delete') { result.code = 'Delete'; result.keyCode = 46; }
    else if (key === 'ArrowUp') { result.code = 'ArrowUp'; result.keyCode = 38; }
    else if (key === 'ArrowDown') { result.code = 'ArrowDown'; result.keyCode = 40; }
    else if (key === 'ArrowLeft') { result.code = 'ArrowLeft'; result.keyCode = 37; }
    else if (key === 'ArrowRight') { result.code = 'ArrowRight'; result.keyCode = 39; }
    else if (key === 'Home') { result.code = 'Home'; result.keyCode = 36; }
    else if (key === 'End') { result.code = 'End'; result.keyCode = 35; }
    else if (key === 'PageUp') { result.code = 'PageUp'; result.keyCode = 33; }
    else if (key === 'PageDown') { result.code = 'PageDown'; result.keyCode = 34; }
    else if (key === 'Insert') { result.code = 'Insert'; result.keyCode = 45; }
    return result;
  }

  function chordMatches(e, chordStr) {
    const parsed = parseChord(chordStr);
    if (!parsed) return false;
    return e.ctrlKey === parsed.ctrlKey &&
      e.metaKey === parsed.metaKey &&
      e.altKey === parsed.altKey &&
      e.shiftKey === parsed.shiftKey &&
      keyNameFromEvent(e) === parsed.key;
  }

  function buildSyntheticEvent(parsed, type) {
    return new KeyboardEvent(type, {
      key: parsed.key,
      code: parsed.code,
      keyCode: parsed.keyCode,
      which: parsed.keyCode,
      ctrlKey: parsed.ctrlKey,
      metaKey: parsed.metaKey,
      altKey: parsed.altKey,
      shiftKey: parsed.shiftKey,
      bubbles: true,
      cancelable: true,
      view: window
    });
  }

  // ---- 原生快捷键合成 ----
  // Tradovate 的 Hotkeys 模块只看 e.key / e.code / 修饰键，不检查 isTrusted，
  // 所以合成 keydown 就能走它自己的下单逻辑（含 ATM 止盈止损）。
  // 原生快捷键优先级：Tradovate 默认 1/2/3 -> 用户记录的原快捷键 -> 点按钮兜底。

  const NATIVE_CHORDS = {
    buy: 'Ctrl+Command+Alt+1',
    sell: 'Ctrl+Command+Alt+2',
    close: 'Ctrl+Command+Alt+3'
  };

  function dispatchNativeChord(chordStr) {
    try {
      const parsed = parseChord(chordStr);
      if (!parsed || String(parsed.key).length !== 1) return false;
      const event = buildSyntheticEvent(parsed, 'keydown');
      event.__tdvHotkeySynthetic = true;
      const target = document.body || document.documentElement || document;
      target.dispatchEvent(event);
      return event.defaultPrevented;
    } catch (err) {
      console.log('[TradingAutoLock hotkey] native dispatch error', err && err.message);
      hotkeyLog('native_dispatch_error', { chord: chordStr, error: truncateText(err && err.message ? err.message : err, 1000) });
      return false;
    }
  }

  function dispatchNativeAction(action) {
    const cfg = hotkeyMap[action];
    const candidates = [];
    if (NATIVE_CHORDS[action]) candidates.push(NATIVE_CHORDS[action]);
    if (cfg && cfg.from && candidates.indexOf(cfg.from) === -1) candidates.push(cfg.from);
    for (let i = 0; i < candidates.length; i++) {
      if (dispatchNativeChord(candidates[i])) {
        console.log('[TradingAutoLock hotkey] native ' + action + ' chord=' + candidates[i] + ' handled=true');
        hotkeyLog('native_result', { action, chord: candidates[i], handled: true });
        return { handled: true, chord: candidates[i] };
      }
      hotkeyLog('native_attempt', { action, chord: candidates[i], handled: false });
    }
    console.log('[TradingAutoLock hotkey] native ' + action + ' not handled, fallback to button click');
    return { handled: false, chord: candidates[candidates.length - 1] || '' };
  }

  // ---- 下单按钮查找与点击（原生快捷键未处理时兜底） ----

  function normalizeActionText(txt) {
    return String(txt || '').replace(/[（(][^)）]*[)）]/g, '').replace(/[\s\u00a0]+/g, '').toLowerCase();
  }

  const ACTION_LABELS = {
    buy: ['buy', 'buymarket', 'marketbuy', '买入', '买', '买进', '市价买入', '市价买', '市价买进'],
    sell: ['sell', 'sellmarket', 'marketsell', '卖出', '卖', '卖空', '市价卖出', '市价卖', '市价卖空'],
    close: ['close', 'flat', 'flatten', 'closeposition', 'flatposition', '平仓', '全部平仓', '市价平仓', '一键平仓', '全平', '退仓', '全部退仓', '市价退仓', '退仓并撤销', '全部退仓并撤销', '市价退仓并撤销', '平仓并撤销', '全部平仓并撤销', '市价平仓并撤销', '清仓', '一键清仓', '全部清仓']
  };

  function findActionButton(action) {
    const labels = ACTION_LABELS[action];
    if (!labels) return null;
    const selectors = ['button', '[role="button"]', '[class*="btn"]', '[class*="Btn"]', 'a'];
    let best = null;
    let bestScore = -1;
    for (const sel of selectors) {
      const els = document.querySelectorAll(sel);
      for (let i = 0; i < els.length; i++) {
        const el = els[i];
        if (el.offsetParent === null && el.getClientRects().length === 0) continue;
        const txt = (el.innerText || el.textContent || '').trim();
        if (!txt || txt.length > 24) continue;
        const normalized = normalizeActionText(txt);
        if (labels.indexOf(normalized) === -1) continue;
        const specific = /market|市价/.test(normalized) ? 1 : 0;
        const score = specific * 1e9 + el.offsetWidth * el.offsetHeight;
        if (score > bestScore) { bestScore = score; best = el; }
      }
    }
    return best;
  }

  function clickTradeButton(action) {
    // 防双触发：window 级标记，script 注入 hook 与 CDP hook 共享
    const guard = window.__tdvClickGuard || { t: 0, action: '' };
    window.__tdvClickGuard = guard;
    const now = Date.now();
    if (guard.action === action && now - guard.t < 800) return true;
    const btn = findActionButton(action);
    if (!btn) {
      console.log('[TradingAutoLock hotkey] no trade button found for ' + action);
      hotkeyLog('button_not_found', { action });
      return false;
    }
    guard.t = now;
    guard.action = action;
    btn.click();
    console.log('[TradingAutoLock hotkey] clicked ' + action + ' button:',
      (btn.innerText || btn.textContent || '').trim().slice(0, 20));
    hotkeyLog('button_clicked', {
      action,
      text: truncateText((btn.innerText || btn.textContent || '').trim(), 80)
    });
    return true;
  }

  // ---- 诊断快照（给 content.js / 诊断包用）----

  function elementVisible(el) {
    if (el.offsetParent !== null) return true;
    const rects = el.getClientRects ? el.getClientRects() : null;
    return Boolean(rects && rects.length);
  }

  function elementRect(el) {
    try {
      const r = el.getBoundingClientRect();
      return {
        left: Math.round(r.left),
        top: Math.round(r.top),
        width: Math.round(r.width),
        height: Math.round(r.height)
      };
    } catch (_) {
      return null;
    }
  }

  function describeElement(el) {
    const text = (el.innerText || el.textContent || '').trim();
    return {
      tag: el.tagName || '',
      id: el.id || '',
      className: truncateText(typeof el.className === 'string' ? el.className : (el.className && el.className.baseVal) || '', 180),
      role: el.getAttribute ? el.getAttribute('role') || '' : '',
      ariaLabel: el.getAttribute ? el.getAttribute('aria-label') || '' : '',
      title: el.getAttribute ? el.getAttribute('title') || '' : '',
      text: truncateText(text, 120),
      normalized: normalizeActionText(text),
      disabled: Boolean(el.disabled),
      visible: elementVisible(el),
      rect: elementRect(el)
    };
  }

  function collectButtonSnapshot() {
    const selectors = ['button', '[role="button"]', '[class*="btn"]', '[class*="Btn"]', 'a'];
    const seen = new Set();
    const rows = [];
    for (const sel of selectors) {
      const els = document.querySelectorAll(sel);
      for (let i = 0; i < els.length; i++) {
        const el = els[i];
        if (seen.has(el)) continue;
        seen.add(el);
        if (!elementVisible(el)) continue;
        const text = (el.innerText || el.textContent || '').trim();
        const aria = el.getAttribute ? (el.getAttribute('aria-label') || el.getAttribute('title') || '') : '';
        if (!text && !aria) continue;
        const normalized = normalizeActionText(text || aria);
        let matchedAction = '';
        for (const action of Object.keys(ACTION_LABELS)) {
          if (ACTION_LABELS[action].indexOf(normalized) !== -1) {
            matchedAction = action;
            break;
          }
        }
        const rect = elementRect(el);
        rows.push({
          ...describeElement(el),
          matchedAction,
          area: rect ? rect.width * rect.height : 0
        });
      }
    }
    rows.sort((a, b) => {
      if (Boolean(b.matchedAction) !== Boolean(a.matchedAction)) return b.matchedAction ? 1 : -1;
      return b.area - a.area;
    });
    return rows.slice(0, 250);
  }

  function collectActionButtonSnapshot() {
    const out = {};
    for (const action of ['buy', 'sell', 'close']) {
      const btn = findActionButton(action);
      out[action] = btn ? describeElement(btn) : null;
    }
    return out;
  }

  function storageHotkeySnapshot(store) {
    if (!store || typeof store.length !== 'number') return { keys: [], hotkeyEntries: [] };
    const keys = [];
    const hotkeyEntries = [];
    try {
      const count = Math.min(store.length, 300);
      for (let i = 0; i < count; i++) {
        const key = store.key(i);
        if (!key) continue;
        keys.push(truncateText(key, 160));
        if (!/hotkey|keybind|shortcut|command|键盘|快捷/i.test(key)) continue;
        let value = '';
        try { value = store.getItem(key) || ''; } catch (_) {}
        hotkeyEntries.push({
          key: truncateText(key, 160),
          length: value.length,
          valuePreview: truncateText(value, 2000)
        });
      }
    } catch (err) {
      return { keys, hotkeyEntries, error: truncateText(err && err.message ? err.message : err, 500) };
    }
    return { keys, hotkeyEntries };
  }

  function accessStorage(kind) {
    try {
      return window[kind] || null;
    } catch (_) {
      return null;
    }
  }

  function collectHotkeyDebugState(requestId) {
    return {
      source: DEBUG_RESPONSE_TYPE,
      requestId: requestId || '',
      ok: true,
      hookBuild: HOOK_BUILD,
      installed: true,
      url: location.href,
      frame: window.top === window.self ? 'top' : 'iframe',
      isTopFrame: window.top === window.self,
      map: hotkeyMap,
      last: window.__tdvHotkeyLast || null,
      logs: hotkeyLogs.slice(-150),
      errors: mainWorldErrors.slice(-60),
      buttons: collectButtonSnapshot(),
      actionButtons: collectActionButtonSnapshot(),
      clickGuard: window.__tdvClickGuard || null,
      configReceivedAt,
      storage: {
        local: storageHotkeySnapshot(accessStorage('localStorage')),
        session: storageHotkeySnapshot(accessStorage('sessionStorage'))
      },
      now: Date.now(),
      nowIso: new Date().toISOString()
    };
  }

  function handleKeydown(e) {
    if (e.__tdvHotkeySynthetic) return; // 自己派发的合成事件，不再拦截
    if (e.__tdvSelfTest) {
      // 自检探针：证明 keydown 监听器确实注册成功且能收到事件
      console.log('[TradingAutoLock hotkey] self-test OK (keydown listener alive) frame='
        + (window.top === window.self ? 'top' : 'iframe'));
      hotkeyLog('self_test_ok', { frame: window.top === window.self ? 'top' : 'iframe' });
      return;
    }
    try {
      window.__tdvHotkeyLast = {
        key: e.key,
        code: e.code,
        chord: formatChord(e),
        matched: false,
        at: Date.now()
      };
    } catch (err) { /* ignore debug snapshot errors */ }
    for (const action of ['buy', 'sell', 'close']) {
      const cfg = hotkeyMap[action];
      if (!cfg || !cfg.to) continue;
      if (chordMatches(e, cfg.to)) {
        e.preventDefault();
        e.stopImmediatePropagation();
        e.stopPropagation();
        const native = dispatchNativeAction(action);
        const clicked = native.handled ? false : clickTradeButton(action);
        try {
          window.__tdvHotkeyLast = {
            key: e.key,
            code: e.code,
            chord: formatChord(e),
            matched: true,
            action: action,
            target: cfg.to,
            nativeChord: native.chord,
            nativeHandled: native.handled,
            clicked: clicked,
            at: Date.now()
          };
        } catch (err) { /* ignore debug snapshot errors */ }
        hotkeyLog('hotkey_match', {
          action,
          target: cfg.to,
          key: e.key,
          code: e.code,
          nativeChord: native.chord,
          nativeHandled: native.handled,
          clicked
        });
        break;
      }
    }
  }
  // window + document 双保险：window capture 理论最先触发，document 作备份
  window.addEventListener('keydown', handleKeydown, true);
  document.addEventListener('keydown', handleKeydown, true);

  // 注入 1.5s 后派发自检探针，直接验证监听器是否注册成功
  setTimeout(function () {
    try {
      const probe = new KeyboardEvent('keydown', {
        key: 'TradingAutoLockSelfTest', code: 'KeyT', bubbles: true, cancelable: true, view: window
      });
      probe.__tdvSelfTest = true;
      window.dispatchEvent(probe);
    } catch (err) {
      console.log('[TradingAutoLock hotkey] self-test dispatch error', err && err.message);
    }
  }, 1500);

  // ---- 配置接收（来自 content.js 的 postMessage）----

  window.addEventListener('message', function (event) {
    if (!event.data || event.data.source !== CONFIG_TYPE) return;
    const map = event.data.map;
    if (map && typeof map === 'object') {
      hotkeyMap = {
        buy: map.buy || DEFAULT_MAP.buy,
        sell: map.sell || DEFAULT_MAP.sell,
        close: map.close || DEFAULT_MAP.close
      };
      window.__tdvHotkeyMap = hotkeyMap;
      configReceivedAt = Date.now();
      console.log('[TradingAutoLock hotkey] config updated platform=tdv',
        'map=' + JSON.stringify(hotkeyMap));
      hotkeyLog('config_updated', { map: hotkeyMap });
    }
  });

  // ---- 诊断请求（来自 content.js 的 postMessage）----
  // content.js 在 ISOLATED world，读不到 MAIN world 的全局变量；
  // 这里把 hook 状态、最近按键、按钮候选、页面错误和 storage 线索一次性回传。

  window.addEventListener('message', function (event) {
    if (!event.data || event.data.source !== DEBUG_REQUEST_TYPE) return;
    const requestId = event.data.requestId || '';
    try {
      window.postMessage(collectHotkeyDebugState(requestId), '*');
    } catch (err) {
      window.postMessage({
        source: DEBUG_RESPONSE_TYPE,
        requestId,
        ok: false,
        error: truncateText(err && err.message ? err.message : err, 1000),
        now: Date.now()
      }, '*');
    }
  });
})();
