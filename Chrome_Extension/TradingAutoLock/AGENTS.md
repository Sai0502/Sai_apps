# AGENTS.md

## What this extension is for

`TradingAutoLock` is a personal Chrome extension (MV3) for trading risk control.

- `https://trader.tradovate.com/*`
  - Reads account PnL and open-position/trade stats from the page and WebSocket capture.
  - Auto-locks the Tradovate account when the configured loss/profit threshold or entry-count limit is reached.
  - Provides one-click manual lock, settings lock, lockout overlay, and a diagnostic bundle.
  - Remaps TDV order hotkeys (buy / sell / close) while leaving the native Tradovate hotkey path intact.
- `https://topstepx.com/*` and `https://*.topstepx.com/*`
  - Walks the Topstep Lockout Controls flow and clicks up to (but not including) the final confirmation.
- TradeSea / TDS support was intentionally removed. Do not reintroduce `tradesea-content.js`, TDS lock rows, or TDS storage keys.

## Critical constraint: page CSP

`trader.tradovate.com` sends CSP with `script-src ... 'strict-dynamic' ...`.
Under CSP3 `strict-dynamic`, `'unsafe-inline'` is ignored. The old approach in
`hotkey-inject.js` (create a `<script>`, set `textContent`, append) was blocked,
so the MAIN-world hook never ran. That file has been deleted.

**Never inline-inject scripts into the page.** Declare page-world code in
`manifest.json` with `"world": "MAIN"` instead. The current hotkey hook is loaded
that way at `document_start` in `all_frames`.

## File map

| File | World / time | Purpose |
| --- | --- | --- |
| `manifest.json` | - | MV3 entrypoint, permissions, content-script ordering |
| `ws-hook.js` | MAIN, `document_start` | Wraps page `WebSocket` and posts captured messages |
| `ws-bridge.js` | ISOLATED, `document_start` | Receives WebSocket capture, derives trade stats |
| `hotkey-hook.js` | MAIN, `document_start`, `all_frames` | TDV hotkey mapper and MAIN-world diagnostic snapshot |
| `content.js` | ISOLATED, `document_idle`, top frame | PnL monitor, auto-lock, overlays, diagnostics, hotkey config delivery |
| `topstep-content.js` | ISOLATED, `document_idle` | Topstep lock flow and its own debug summary |
| `background.js` | service worker | Installs defaults, opens popup on request |
| `popup.html/css/js` | extension page | Settings, manual lock, hotkey editor, diagnostic summaries |
| `test/*.mjs` | Node | Mock-DOM verification scripts (repo-local, no browser needed) |

## TDV hotkey design

The hook works in three layers:

1. Listen to `keydown` on `window` and `document` in capture phase.
2. Match the user's `to` chord using `e.code` (not just `e.key`), so Space,
   `Option+1`, and Chinese IME `Process` keys behave correctly.
3. On a match:
   - `preventDefault` + `stopImmediatePropagation` + `stopPropagation`;
   - synthesize a native Tradovate chord (`Ctrl+Command+Alt+1/2/3`);
   - if the page does not consume it, fall back to clicking a matching order
     button (`findActionButton`).

The native path matters because it goes through Tradovate's own order logic,
including ATM take-profit / stop-loss brackets. A raw button click does not
attach those brackets.

Mapping storage and flow:

- Stored in `chrome.storage.local` under `tdvHotkeyMap`
  (`{buy:{from,to}, sell:{from,to}, close:{from,to}}`).
- Popup saves the map and sends `tradovate-auto-lock:hotkey-update` to the tab.
- `content.js` stores it, then posts `tradovate-auto-lock:hotkey-config` via
  `window.postMessage`.
- `hotkey-hook.js` receives it and updates `window.__tdvHotkeyMap`.
- On page load `content.js` reads storage and posts the config again.
- Only the top-frame `content.js` posts config; the hook still runs in frames.

Useful page globals (MAIN world, visible in DevTools):

- `window.__tdvHotkeyMap` - currently effective map.
- `window.__tdvHotkeyLast` - last key event: `chord`, `matched`, `action`,
  `nativeChord`, `nativeHandled`, `clicked`.
- `window.__tdvClickGuard` - 800 ms fallback-click debounce.

If a hotkey does nothing, first check `window.__tdvHotkeyLast`:

- no object at all: hook not installed / wrong frame / manifest problem;
- `matched:false`: `to` mapping or `e.code` mismatch;
- `nativeHandled:false` and `clicked:false`: native chord not consumed and no
  matching button label.

## Auto-lock flow (Tradovate)

`monitorScan` in `content.js`:

1. Resolve the current account ID from the page.
2. Read account-scoped monitor settings.
3. Extract PnL / equity and trade stats.
4. Decide loss / profit / entry-count threshold.
5. If triggered and not already locked, set auto state to `locking` and call
   `executeRealLockout`.
6. `executeRealLockout` opens `手动锁定`, selects the account and duration,
   fills the custom-time subdialog when needed, confirms, waits for
   `账户已锁定`, and persists state.

Known fragile area: `setCustomLockTime` / `fillCustomLockTime` locate the modal
by text. `findVisibleModalRootByText` can match the outer
`.manual-lockout-modal__body` instead of the custom-time subdialog, which yields
zero time inputs (`custom_time_set_failed`, `fieldCount:0`). If auto-lock fails
with that error, inspect the diagnostic bundle's `domDiagnostics`,
`runtimeDiagnosticEvents`, and `debugLogTail` before changing selectors.

Do not hardcode the auto-lock target to `04:00`; the configured
`lockDuration` (`custom_HHMM`) is authoritative.

## Diagnostic bundle

The bundle is written for an AI/engineer, not for end users. It is produced by
`content.js` `buildDiagnosticBundle()` and assembled by `popup.js`.

Main sections:

- page / build / account / browser environment / permissions;
- feature detection / performance / WebSocket capture;
- `pageStructure`, `pnlExtraction`, `domDiagnostics`;
- `hotkey`: result of `tradovate-auto-lock:hotkey-debug-request`;
- runtime diagnostic events and debug-log tail;
- account-scoped storage snapshots and `tdvHotkeyMap`.

The hotkey debug response includes `hookBuild`, `installed`, frame/top-frame,
effective map, `__tdvHotkeyLast`, recent hook logs, MAIN-world errors, visible
button candidates with rects, resolved buy/sell/close buttons, click guard,
config receipt time, and hotkey-related localStorage/sessionStorage entries.

Popup outputs three levels: Summary (markdown, default), Detailed, Raw. Keep all
three working; Summary is what a human pastes first.

## Storage keys

Account-scoped suffix is `:${accountId || 'default'}`.

- `tradovateSettingsLockedUntil:<account>`
- `tradovateMonitorSettings:<account>`
- `tradovateRuntimeState:<account>`
- `tradovateAutoLockState:<account>`
- `tradovateLockoutOverlayState:<account>`
- `tdvHotkeyMap` (global, not account-scoped)
- `tradovateWsCapture` (global WebSocket capture)
- `tradovateAutoLockStepOffsets`
- `debugLog`

## Version rule

Build labels use `vMMDD_HHMM`, where the digits are the local date/time of the
last edit: `v1024_1246` = Oct 24, 12:46. Keep these in sync when making a
release-worthy change:

- `content.js` `SCRIPT_BUILD_LABEL`
- `popup.js` `POPUP_BUILD_LABEL`
- `popup.html` `<h1 id="appTitle">`
- `hotkey-hook.js` `HOOK_BUILD`
- `topstep-content.js` `SCRIPT_BUILD_LABEL`

`content.js` `SCRIPT_VERSION` is the idempotent-load guard; bump it whenever
content-script logic changes.

## Local verification

Run from the extension directory:

```bash
node --check content.js
node --check popup.js
node --check hotkey-hook.js
node --check topstep-content.js
node -e "JSON.parse(require('fs').readFileSync('manifest.json','utf8'))"
node test/verify_hotkey_mapping.mjs
```

`test/verify_hotkey_mapping.mjs` is a dependency-free Node/vm harness with a
mock DOM. Most legacy `test/verify_*.mjs` files require a machine-specific
Playwright install, so they may not run on every machine. `test/mock_*.html`
are manual page fixtures for the lock flows.

Never commit unless the user explicitly asks. Do not touch unrelated files in
the workspace.
