// TradingAutoLock hotkey-hook.js (MAIN world, document_start)
// 在页面脚本之前注入，最早捕获 keydown。用户配置"原快捷键 -> 新快捷键"映射，
// 按下新快捷键时拦截并合成派发原快捷键事件，让 Tradovate 执行对应下单动作。
(function () {
  const HOOK_FLAG = '__tradingAutoLockHotkeyHookInstalled';
  const CONFIG_TYPE = 'tradovate-auto-lock:hotkey-config';
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
    return c;
  }

  function keyNameFromEvent(e) {
    const k = e.key;
    // 中文输入法活跃时（keyCode 229），空格/字母等 e.key 可能变成 'Process'/'Unidentified'，
    // 此时改用 e.code 识别（空格恒为 Space，不受输入法影响）
    if (!k || k === 'Dead' || k === 'Unidentified' || k === 'Process') {
      return codeNameFromEvent(e);
    }
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

  // ---- 下单按钮查找与点击（不依赖页面快捷键） ----
  // 拦截新键后直接查找并点击页面上的下单按钮（Buy/Sell/Close/平仓），
  // 不依赖页面是否提供可被合成事件触发的快捷键，点击必然生效。

  function findActionButton(action) {
    const selectors = ['button', '[role="button"]', '[class*="btn"]', '[class*="Btn"]', 'a'];
    let best = null;
    let bestScore = -1;
    for (const sel of selectors) {
      const els = document.querySelectorAll(sel);
      for (let i = 0; i < els.length; i++) {
        const el = els[i];
        if (el.offsetParent === null && el.getClientRects().length === 0) continue; // 不可见
        const txt = (el.innerText || el.textContent || '').trim();
        if (!txt || txt.length > 24) continue;
        const lower = txt.toLowerCase();
        let hit = false;
        if (action === 'buy') {
          hit = lower === 'buy' || lower === 'buy market' || /^buy\s*$/.test(lower);
        } else if (action === 'sell') {
          hit = lower === 'sell' || lower === 'sell market' || /^sell\s*$/.test(lower);
        } else {
          hit = /^(close|flat|flatten|close position|平仓)$/.test(lower);
        }
        if (hit) {
          const score = el.offsetWidth * el.offsetHeight;
          if (score > bestScore) { bestScore = score; best = el; }
        }
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
      return false;
    }
    guard.t = now;
    guard.action = action;
    btn.click();
    console.log('[TradingAutoLock hotkey] clicked ' + action + ' button:',
      (btn.innerText || btn.textContent || '').trim().slice(0, 20));
    return true;
  }

  function handleKeydown(e) {
    if (e.__tdvHotkeySynthetic) return; // 自己派发的合成事件，不再拦截
    if (e.__tdvSelfTest) {
      // 自检探针：证明 keydown 监听器确实注册成功且能收到事件
      console.log('[TradingAutoLock hotkey] self-test OK (keydown listener alive) frame='
        + (window.top === window.self ? 'top' : 'iframe'));
      return;
    }
    for (const action of ['buy', 'sell', 'close']) {
      const cfg = hotkeyMap[action];
      if (!cfg || !cfg.to) continue;
      if (chordMatches(e, cfg.to)) {
        e.preventDefault();
        e.stopImmediatePropagation();
        e.stopPropagation();
        clickTradeButton(action);
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
      window.dispatchEvent(new KeyboardEvent('keydown', {
        key: 'TradingAutoLockSelfTest', code: 'KeyT', bubbles: true, cancelable: true, view: window
      }));
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
      console.log('[TradingAutoLock hotkey] config updated platform=tdv',
        'map=' + JSON.stringify(hotkeyMap));
    }
  });
})();
