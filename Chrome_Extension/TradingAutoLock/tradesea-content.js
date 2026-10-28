// TradingAutoLock tradesea-content.js
// TradeSea (app.tradesea.ai) 锁定流程：
//   1. 点击屏幕右上角的锁型图标
//   2. 弹出 "Personal Lockout" 面板
//   3. 在 "Enter Custom hours" 下的小时输入栏填入锁定小时数（先固定 2，算法待接入）
//   4. 点击右下角 "SET LOCKOUT" 按钮
// 与 topstep-content.js 的 TS 锁定同样模式：popup 点击按钮 → 本脚本执行 UI 自动化。
(function () {
  const SCRIPT_BUILD_LABEL = 'TradingAutoLock-TDS v1024_1244';
  const MSG_TYPE = 'tradovate-auto-lock:tds-lock';
  const DEFAULT_HOURS = 2;

  console.log('[' + SCRIPT_BUILD_LABEL + '] loaded url=' + location.href);

  chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
    if (!message || message.type !== MSG_TYPE) return false;
    (async () => {
      const hours = typeof message.hours === 'number' && message.hours > 0 ? message.hours : DEFAULT_HOURS;
      const log = [];
      try {
        const detail = await runLockout(hours, log);
        console.log('[TDS lock] ok', detail);
        sendResponse({ ok: true, hours, log, ...detail });
      } catch (err) {
        console.warn('[TDS lock] failed', err && err.message);
        sendResponse({ ok: false, error: err && err.message ? err.message : String(err), log });
      }
    })();
    return true;
  });

  function sleep(ms) {
    return new Promise(resolve => window.setTimeout(resolve, ms));
  }

  async function waitFor(fn, timeoutMs, intervalMs, label, log) {
    const t0 = Date.now();
    let lastErr = null;
    while (Date.now() - t0 < timeoutMs) {
      try {
        const v = fn();
        if (v) return v;
      } catch (err) {
        lastErr = err;
      }
      await sleep(intervalMs);
    }
    throw new Error('等待超时：' + label + (lastErr ? '（' + (lastErr.message || lastErr) + '）' : ''));
  }

  function isVisible(el) {
    if (!el || !el.isConnected) return false;
    if (el.offsetParent === null && el.getClientRects().length === 0) return false;
    const style = window.getComputedStyle(el);
    if (style.display === 'none' || style.visibility === 'hidden' || Number(style.opacity) === 0) return false;
    const r = el.getBoundingClientRect();
    return r.width > 2 && r.height > 2;
  }

  function closestDialog(el) {
    let cur = el;
    while (cur && cur !== document.body) {
      const cls = String(cur.className || '').toLowerCase();
      const id = String(cur.id || '').toLowerCase();
      if (/modal|dialog|popup|panel|overlay|layer|window/.test(cls + ' ' + id)) return cur;
      cur = cur.parentElement;
    }
    return el.parentElement || el;
  }

  // ---- 定位元素 ----

  // 右上角锁型图标。TradeSea 为 React 应用，图标无统一文字；
  // 先按 lock 特征扫描，失败则退回右上角区域内可点击元素（带诊断信息）。
  function findLockIcon(candidatesOut) {
    const cands = Array.from(document.querySelectorAll(
      'button, [role="button"], [class*="icon"], [class*="Icon"], svg, a, [tabindex]'
    ));
    // 候选 A：title/aria-label/id/class 含 lock
    for (const el of cands) {
      const hay = String(
        (el.getAttribute && (el.getAttribute('title') || el.getAttribute('aria-label') || '')) || ''
      ) + ' ' + String(el.id || '') + ' ' + String(el.className || '');
      if (/lock/i.test(hay) && isVisible(el)) {
        const r = el.getBoundingClientRect();
        // 要求位于视口右上区（避免点到页面其他地方的同名元素）
        if (r.left > window.innerWidth * 0.55 && r.top < window.innerHeight * 0.3) return el;
      }
    }
    // 候选 B：右上角区域（右 25% × 顶 18%）内的可见可点击元素
    const w = window.innerWidth, h = window.innerHeight;
    const x0 = w * 0.75, y0 = h * 0.015, x1 = w * 0.995, y1 = h * 0.18;
    const inZone = cands.filter(el => {
      if (!isVisible(el)) return false;
      const r = el.getBoundingClientRect();
      if (r.width * r.height < 100) return false;
      return r.left < x1 && r.top < y1 && r.right > x0 && r.bottom > y0;
    });
    if (inZone.length) {
      // 取最靠右上角的
      inZone.sort((a, b) => {
        const ra = a.getBoundingClientRect(), rb = b.getBoundingClientRect();
        return (rb.right + rb.bottom) - (ra.right + ra.bottom);
      });
      if (candidatesOut) {
        candidatesOut.length = 0;
        for (const el of inZone.slice(0, 8)) {
          const r = el.getBoundingClientRect();
          candidatesOut.push({
            tag: el.tagName,
            cls: String(el.className || '').slice(0, 60),
            title: (el.getAttribute && el.getAttribute('title')) || '',
            aria: (el.getAttribute && el.getAttribute('aria-label')) || '',
            x: Math.round(r.left), y: Math.round(r.top)
          });
        }
      }
      return inZone[0];
    }
    return null;
  }

  // "Personal Lockout" 弹窗主体（含标题文本的最近容器）
  function findDialog() {
    const all = Array.from(document.querySelectorAll('div, section, aside, form, [role="dialog"], [class*="modal"], [class*="popup"]'));
    for (const el of all) {
      if (!isVisible(el)) continue;
      const txt = (el.textContent || '');
      if (txt.indexOf('Personal Lockout') !== -1 && txt.length < 2000) {
        return closestDialog(el);
      }
    }
    return null;
  }

  // "Enter Custom hours" 可点击区域（切换自定义模式）
  function findEnterCustom() {
    const all = Array.from(document.querySelectorAll('button, [role="button"], label, div, span'));
    for (const el of all) {
      if (!isVisible(el)) continue;
      const direct = Array.from(el.childNodes).filter(n => n.nodeType === 3).map(n => n.textContent).join(' ');
      if (/Enter Custom hours/i.test(direct) || /^Enter Custom hours$/.test((el.textContent || '').trim())) {
        return el;
      }
    }
    return null;
  }

  // 小时数输入栏：弹窗内的可见 input（text/number）
  function findHoursInput(dialog) {
    const scope = dialog || document;
    const inputs = Array.from(scope.querySelectorAll('input'));
    for (const el of inputs) {
      const t = String(el.type || '').toLowerCase();
      if (t === 'checkbox' || t === 'radio' || t === 'hidden' || t === 'password' || t === 'file') continue;
      if (!isVisible(el)) continue;
      const r = el.getBoundingClientRect();
      if (dialog && (r.top < dialog.getBoundingClientRect().top - 40 || r.bottom > dialog.getBoundingClientRect().bottom + 40)) continue;
      return el;
    }
    return null;
  }

  // SET LOCKOUT 按钮
  function findSetLockout(dialog) {
    const scope = dialog || document;
    const all = Array.from(scope.querySelectorAll('button, [role="button"]'));
    for (const el of all) {
      if (!isVisible(el)) continue;
      const txt = (el.textContent || '').trim().toLowerCase();
      if (txt === 'set lockout' || txt === 'setlockout' || /^set lockout\b/.test(txt)) return el;
    }
    return null;
  }

  // 成功确认：弹窗出现 LOCKOUT SET FOR 或 CLEAR 按钮
  function findLockoutSet(dialog) {
    if (!dialog) return false;
    const txt = (dialog.textContent || '').toUpperCase();
    if (txt.indexOf('LOCKOUT SET') !== -1) return true;
    const btns = Array.from(dialog.querySelectorAll('button, [role="button"]'));
    return btns.some(b => (b.textContent || '').trim().toUpperCase() === 'CLEAR');
  }

  // React 受控组件填值：走原生 value setter
  function setNativeValue(el, value) {
    const proto = Object.getPrototypeOf(el);
    const desc = Object.getOwnPropertyDescriptor(proto, 'value');
    if (desc && desc.set) {
      desc.set.call(el, value);
    } else {
      el.value = value;
    }
  }

  async function runLockout(hours, log) {
    log.push('TDS 锁定开始，小时数=' + hours);
    log.push('url=' + location.href);

    // 1. 弹窗可能已打开（用户手动点过锁图标）；未打开则点击锁图标
    let dialog = findDialog();
    if (!dialog) {
      const candidates = [];
      const icon = findLockIcon(candidates);
      if (!icon) {
        const info = candidates.length
          ? '右上角候选元素: ' + JSON.stringify(candidates)
          : '右上角无可点击元素';
        throw new Error('第 1 步失败：找不到右上角锁图标。' + info);
      }
      icon.click();
      log.push('第 1 步：已点击锁图标 tag=' + icon.tagName + ' cls=' + String(icon.className || '').slice(0, 50));
      dialog = await waitFor(findDialog, 8000, 250, 'Personal Lockout 弹窗', log);
      log.push('弹窗已出现');
    } else {
      log.push('弹窗已打开（跳过锁图标）');
    }

    // 2. 确保进入 "Enter Custom hours" 模式
    const custom = findEnterCustom();
    if (custom) {
      custom.click();
      log.push('第 2 步：已点击 "Enter Custom hours"');
      await sleep(400);
    } else {
      log.push('第 2 步：未找到 "Enter Custom hours" 文本（弹窗可能已处于自定义模式）');
    }

    // 3. 填入小时数
    const input = await waitFor(() => findHoursInput(dialog), 6000, 250, '小时数输入栏', log);
    setNativeValue(input, String(hours));
    input.dispatchEvent(new window.Event('input', { bubbles: true }));
    input.dispatchEvent(new window.Event('change', { bubbles: true }));
    await sleep(300);
    log.push('第 3 步：已填入 ' + hours + '（input type=' + input.type + '）');

    // 4. 点击 SET LOCKOUT
    const btn = await waitFor(() => findSetLockout(dialog), 5000, 250, 'SET LOCKOUT 按钮', log);
    const before = findLockoutSet(dialog);
    btn.click();
    log.push('第 4 步：已点击 SET LOCKOUT');

    // 5. 确认成功（状态文本变为 LOCKOUT SET / CLEAR；最多等 6s）
    let confirmed = before;
    const t0 = Date.now();
    while (Date.now() - t0 < 6000) {
      const now = findLockoutSet(dialog);
      if (now && !before) { confirmed = true; break; }
      if (now) confirmed = true;
      await sleep(300);
    }
    log.push(confirmed ? '第 5 步：已确认锁定生效' : '第 5 步：未检测到确认文本（流程已执行，可查看页面）');
    return { dialogText: (dialog.textContent || '').slice(0, 120) };
  }
})();
