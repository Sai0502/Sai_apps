# 全屏 Space 里唤不出底部弹窗（2026-11-14）

这份记录是给"问题又出现时"看的：先按【怎么确认是不是同一问题】查日志，再按【如果复发】往下走。
不要凭感觉改 `NSApp.activate`，那是被这次修复刻意去掉的东西。

## 现象

- 别的 App 处于全屏 Space（全屏 Chrome / 全屏视频）时按热键，底部弹窗**不出现**。
- 从那片 Space 切回桌面后，弹窗**就摆在桌面上**（不是重新出现，是它本来就在那儿）。
- 偶发：有时正常，所以很难主动复现——这也是当初没被发现的原因。

## 怎么确认是不是同一问题

### 1. 看日志

```bash
/usr/bin/log show --last 10m --predicate 'subsystem == "com.greycorelabs.saipaste"' --style compact \
  | grep -E 'show|settle|focus|resignKey|rekey|fallback'
```

**有问题的特征序列**（旧版本每次必现）：

```
AppKit: Window <SaiPaste.BarPanel> windowNumber=… ordered front from a non-active
        application and may order beneath the active application's windows.
show: appActive=false windowKey=false appPolicy=1
       … +0.22s …
show settle: key=true active=true
focus: app=true run=true key=true front=SaiPaste      ← 前台变成了自己（坏）
       … 0.8–2.5s 后 …
resignKey: newKey=nil appActive=false phase=shown
order window: … op: 0                                  ← 随即 orderOut，弹窗自己收起
```

**修复后正常的样子**：

```
show: appActive=false windowKey=true appPolicy=1
show settle: key=true active=true
focus: app=true run=false key=true front=Google Chrome  ← 前台仍是原来那个 App（对）
```

判断要点：`focus:` 那行的 `front=` 应该是**触发热键前的前台 App**，不是 SaiPaste。
`run=` 是 `NSRunningApplication.current.isActive`，正常修复后是 `false`。

### 2. 看弹窗到底落在哪片 Space

弹窗是 `BarPanel`，level 8（`.modalPanel`）。用它自己的窗口号/层级判断它有没有被搬走：

```bash
cd /private/var/folders/6x/pv_drmws4plf30mswz3x_4nc0000gn/T/opencode && ./wins
```

（`wins` 是一个列出 `CGWindowListCopyWindowInfo` 里 on-screen 窗口的小工具，源码见文末。
临时目录被清掉时按文末源码重新 `swiftc` 一个即可。）

- **正常**：全屏窗口（0,0 起、铺满整块屏）和 `SaiPaste … layer=8 onscreen=true` 同时出现在列表里。
- **异常**：当前 Space 里只有全屏窗口，没有 `SaiPaste`；切到桌面 Space 才看见 `layer=8` 的它。

### 3. 先排除"热键根本没送到"

没日志 ≠ 窗口有问题。先确认这次按键有没有触发 `show:` 行，没有的话是热键问题（见文末干扰项）。

## 根因

`show()` 原本在把面板 `orderFront` 之后，会激活自己：

```swift
panel.orderFrontRegardless()
panel.makeKeyAndOrderFront(nil)
NSApp.activate(ignoringOtherApps: true)
NSRunningApplication.current.activate(options: [.activateAllWindows])
```

SaiPaste 是 `LSUIElement`（无 Dock 图标）的 accessory App。全屏 Space 只容纳全屏 App 自己的窗口，
SaiPaste 在那里一个窗口都没有；此时激活它，WindowServer 会把它的窗口**搬到普通桌面 Space**。
结果就是：面板确实上屏了，但上在桌面 Space；全屏 Space 前面什么都没有。
面板随后因为拿不到 key（`windowDidResignKey` → `hideBar()`）又收了起来，于是"按了没反应"。

窗口的 `collectionBehavior` 和 `level` 都不是元凶：`.stationary` / `.canJoinAllSpaces` / `.fullScreenAuxiliary`
在修复前后完全没动，问题照样解决。**只改激活行为就够了。**

## 修复内容

文件：`Sources/SaiPaste/UI/BarWindowController.swift`

1. `init()`：`styleMask: [.borderless]` → `[.borderless, .nonactivatingPanel]`，
   并显式 `panel.becomesKeyOnlyIfNeeded = false`（点击和 ⌘ 组合键要能落到面板上）。
2. `show()`：删掉两处 `activate`，改成

   ```swift
   panel.orderFrontRegardless()
   panel.makeKey()
   ```

3. `ensureKey()`：`makeKeyAndOrderFront(nil)` → `makeKey()`；rekey 从 6 次缩到 `[0.05, 0.15]` 两次。
4. `settle` 的兜底隐藏：0.12s → 0.35s，并在隐藏前再 `ensureKey()` 一次，日志标记 `settle fallback hide`。

原理：`.nonactivatingPanel` 允许面板**在不激活 App 的前提下成为 key window**。
键盘事件仍然进入本 App，`AppController.startKeyMonitor()` 的 local monitor 照常收到并路由到搜索框，
所以不需要切前台 App，也就不会触发 Space 搬迁。

## 副作用：Enter / 双击卡片粘贴失效（同日修复）

上面的改动上线后立刻踩到一个副作用：弹出正常、打字正常，但按 Enter 或双击卡片
**只能听到"咚"的一声**，什么都没粘上。

原因：面板是非激活面板，`PasteService` 里的 `target.activate()` 对"本来就在前台"的
目标 App 是空操作，于是没有人把 key 从面板手上拿走。而 `hide()` 要等 0.16s 收场动画结束
才 `orderOut`，粘贴路径在这之前就把合成 ⌘V 发出去了——这笔事件被投递回 SaiPaste 自己，
卡片模式下无人处理，系统就 beep。

日志特征（出问题时一定是这样）：

```
key code=36 … mode=cards                      ← 按了 Enter
tccd: kTCCServicePostEvent authValue=2         ← ⌘V 真的发出去了（有权限）
resignKey: … phase=hiding                      ← 但面板到这时才让出 key
```

修复（三处）：

1. `BarWindowController.hide()`：进入 `.hiding` 后立刻 `panel.resignKey()`，
   不等 `orderOut`。此时 `phase` 已是 `.hiding`，`windowDidResignKey` 的
   `phase == .shown` 守卫不会让它递归再收一次。
2. `BarWindowController.holdsKeyWindow` / `AppController.barHoldsKeyWindow`：
   暴露"面板是否还占着 key window"。
3. `PasteService.waitForFrontmost`：结束条件从"目标 App 已前台"改为
   **"目标 App 已前台 且 面板已让出 key"**，等待期间每 30ms 轮询（最多 20 次，
   600ms 封顶）；超时会打 `paste: gave up waiting …`，并继续照常发送，
   不会把粘贴整个吞掉。

成功时日志是：

```
hide: resigned key key=false
paste: front=文本编辑 keyReleased=true
```

## 诊断埋点（长期保留，仅写日志不改行为）

- `toggleBar()`：`hotkey: presented=… front=…` —— 证明热键确实到达了 SaiPaste。
- `show()`：`show: screen=<目标屏幕 visibleFrame> front=<App>(fullscreen=yes/no)`
  —— 记录弹窗瞄准了哪块屏幕、当时前台是谁、它是不是全屏窗口。
- `windowDidResignKey`：带上 `sinceSettle=`（距离弹窗落定多久），
  且**在落定后 0.4s 内失焦不再立刻收起**，而是再等一次确认——
  避免焦点短暂抖动让弹窗"闪一下就没"，读起来像"热键没反应"。

有这三条，下次真复发时 `log show` 就能直接回答：
热键到没到 / 弹窗瞄了哪块屏 / 前台是不是全屏 / 是不是刚出现就丢了焦点。

## 修复后的自检（改完/怀疑回归时跑一遍）

1. 全屏 Chrome（⌃⌘F）里按热键：弹窗出现在全屏画面底部，Space 不切换。
2. 全屏里直接打字：第一个字母进搜索框；↑↓ 选择；Esc 收起；**Enter 能把内容粘回 Chrome**。
3. 桌面 Space 按热键：**第一个字母**同样要进搜索框（这是本次改动最主要的回归风险点）。
4. 点卡片粘贴、**双击卡片粘贴**（走同一条 `PasteService.paste`，Enter 好它就一定好）、
   点面板外收起、⌘A 全选、⌘⇧S 开设置。
5. 多 Space：在 Space 2 按热键，弹窗出现在 Space 2。
6. 多屏：指针在副屏时弹窗出现在副屏。
7. 日志：`focus: … front=` 是原 App；`show` 之后不再紧跟 `resignKey … phase=shown`。

## 如果复发（按顺序升级，一次只动一处）

1. `collectionBehavior` 换成 Maccy 的方案：
   `[.auxiliary, .stationary, .moveToActiveSpace, .fullScreenAuxiliary]`
   （去掉 `.canJoinAllSpaces`，让面板"跟着当前 Space 走"而不是"存在于所有 Space"）。
2. `panel.level` 提到 `.statusBar`（25）；同时把 `CopyToastController` 的 `.floating` 抬到它之上，
   否则"未获得辅助功能权限"的提示会被压在弹窗底下。
3. 只有在"全屏 Space 里仍然拿不到 key"（日志 `settle: key=false`）时，才考虑
   **只对全屏 Space** 保留激活路径的分支实现，桌面 Space 继续走非激活路径。
4. 不要把 `NSApp.activate` 加回主路径，那正是这次要修的东西。

## 排查时的干扰项

- **热键不是 ⌘⇧V**。当前机器上 `defaults read com.greycorelabs.saipaste` 里是
  `hotkeyKeyCode = 1`（S）、`hotkeyModifiers = 2048`（optionKey），也就是 **⌥S**。
  ⌘⇧V 是 Alfred 的剪贴板历史，按它只会弹出 Alfred，SaiPaste 不会有任何日志。
- 合成按键不可靠：`osascript … keystroke` 在缺少辅助功能/自动化授权时会静默失败
  （`osascript 不允许发送按键`，错误 1002）；`CGEvent` 合成同理。
  判定"热键没反应"之前，先看日志里有没有 `show:` 行。
- 残留的其它全屏 App 会占用一整片 Space（当时就有一个测试用的小 App 一直挂着全屏），
  `./wins` 里看到的"当前 Space"可能根本不是你以为的那片。
- `screencapture` 抓的是**当前 Space**。在错误的 Space 上截图，会得到一张看着"什么都没有"的图，
  不要据此判断弹窗没出现。

## 附：`wins` 源码（窗口层级/位置速查）

```swift
import CoreGraphics
import Foundation

let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
guard let list = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else { exit(1) }
for w in list {
    let owner = w[kCGWindowOwnerName as String] as? String ?? "?"
    let num = w[kCGWindowNumber as String] as? Int ?? 0
    let layer = w[kCGWindowLayer as String] as? Int ?? 0
    let onscreen = w[kCGWindowIsOnscreen as String] as? Bool ?? false
    let b = w[kCGWindowBounds as String] as? [String: Any] ?? [:]
    let x = b["X"] as? Double ?? 0, y = b["Y"] as? Double ?? 0
    let wd = b["Width"] as? Double ?? 0, ht = b["Height"] as? Double ?? 0
    print("\(owner) win=\(num) layer=\(layer) onscreen=\(onscreen) frame=(\(Int(x)),\(Int(y)),\(Int(wd)),\(Int(ht)))")
}
```

编译：`swiftc -O wins.swift -o wins`
