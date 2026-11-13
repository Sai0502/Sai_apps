# SaiShot 项目全程记录（交接文档）

> 用途：把这份文档喂给另一个 AI，让它在不重走弯路的前提下接手这个 macOS 截图/贴图 App。
> 记录时间：2026-11-10 12:45（Asia/Shanghai）。
> 2026-11-11 更新：已全量改名 `SaiShotJunior` → `SaiShot`（工程目录、显示名、可执行名、bundle id `cn.skyrin.saishot`、URL scheme `saishot://`、历史目录），历史从空开始。
> 重要：下文第 1、3、11 节保留改名前的历史状态，阅读时以最新状态为准。

---

## 0. 一句话背景

这是一个从开源项目 **CapCap** 二创出来的 macOS 截图 + 贴图工具。二创版本先叫 `SaiShot`（bundle id `cn.skyrin.saishot`），后来为了不动原工程、单独做实验，复制出一份 **`SaiShotJunior`**（bundle id `cn.skyrin.saishotjunior`）。所有新功能都先在 Junior 上做，验证通过后再考虑合并。最终用户决定：**不合并，Junior 就是唯一在用的最终版本**。2026-11-11 用户又决定全量改回 `SaiShot`，工程目录、显示名、可执行名、bundle id、URL scheme、历史目录都已同步，旧的 Junior 身份不再使用。

全程没有提交过 git commit：所有修改都在工作区（`git diff`）里，HEAD 停在 `1e9afb9`。

---

## 1. 当前状态快照

| 项 | 值 |
|---|---|
| 工程路径（唯一在用） | `/Users/sai/Documents/GitHub/Sai_apps/SaiShot` |
| git HEAD | `1e9afb9 调整: 窗口截图投影尺寸 22 → 44（2 倍）` |
| 工作区改动 | 约 18–19 个文件，`+52x / −62x`（以 `git status` 为准） |
| bundle id | `cn.skyrin.saishot` |
| 显示名 / 可执行名 | `SaiShot` |
| URL scheme | `saishot://edit?file=<绝对路径>` |
| 运行中的副本 | **只有** `build/SaiShot.app`（`/Applications` 那份已被用户删除） |
| 签名身份 | 自签名证书 `SaiShot Self-Signed`（SHA1 `4929ED3F…D70E`） |
| Designated Requirement | `identifier "cn.skyrin.saishot" and certificate root = H"4929ed3f3e7732acac354d7755d3692cb694d70e"` |
| 权限 | 改名后需重新授权屏幕录制、辅助功能、麦克风 |
| 历史截图目录 | `~/Library/Application Support/SaiShot/History`（改名后从空开始，旧 `SaiShotJunior` 历史未导入） |
| 另一份工程 | `SaiShot_1109`（曾做过合并，用户已自行归档，别动） |

---

## 2. 来源与更名史（二创阶段）

上游：开源项目 **CapCap**。二创过程在 git 历史里能看到（都在同一仓库内，未提交的部分另说）：

| commit | 做了什么 |
|---|---|
| `b9d36b2` | 删掉多图拼接功能（ImageMerge）；菜单栏「截全屏」改成「贴图」，剪贴板没有图时静默处理 |
| `bd0f9d2` | 启动即进菜单栏（去掉启动/退出按钮和启动弹窗）；文件与输出设置并入「通用」；贴图按逻辑尺寸还原 |
| `37248fc` | 设置大裁剪：删「截图与贴图 / 历史记录 / 文字识别 / 关于」四个 tab，历史数量与 OCR 并入通用；钉窗工具条去掉关闭按钮与拖动柄；倒计时整体移除；窗口阴影恒开 22、贴图不跨桌面、历史缓存恒开 |
| `6c1cb30` | 历史数量文案、钉窗工具条去取景框、快捷键行加「清除叉号」并可真正置空、编辑钉窗图时裁掉投影透明边 |
| `26fa2e7` | feat(pin)：空格/Esc 往返就地编辑已钉住的图 |
| `cf736ce` | **全量更名 capcap → SaiShot**（模块名、显示名、Info.plist 等） |
| `f6504b8` | 去掉发布用资产；界面语言收敛为「简体中文 + English」 |
| `34d1820` | 删失效的 agent-tools 文档，版本号提到 1.8.0 |
| `1e9afb9`（HEAD） | 窗口截图投影尺寸 22 → 44（2 倍），钉住的图能看出悬浮阴影 |

这个阶段还做过：删掉 9 份 README、`images/`、`CHANGELOG.md`、`THEME_ADAPTATION_AUDIT.md`、`LICENSE`、`.github/`、DMG/签名脚本、`scripts/signing/`、`SaiShot-agent-tools/`、`output/`、全部 `.DS_Store`、`Tests/.../TempShadowPreviewTests.swift`、`SaiShot/Utilities/DebugLog.swift`。

---

## 3. 为什么曾分裂出独立实验版本（SaiShotJunior）

原 `SaiShot.app`（`cn.skyrin.saishot`）已经装在本机、有历史截图和一套设置。改功能时想保留一个可回退的干净版本，于是把整个工程目录复制成 `SaiShot_副本`，并把它变成一个**独立身份**的 App：

- bundle id 改成 `cn.skyrin.saishotjunior`
- 显示名、可执行名、菜单名跟着改
- URL scheme 改成 `saishotjunior://`
- 独立 UserDefaults 域 `cn.skyrin.saishotjunior`、独立历史目录

好处：两个 App 能在系统设置、活动监视器里分得清，授权互不干扰，设置不串。代价：设置要重配一遍、历史不共享、URL 协议变了。

最后用户决定 **Junior 当唯一版本**，不合并了（理由：两个工程本是同一提交的两份拷贝，合并只是把改动抄回去，抄完还是两个工程；而且合并过程要在屏幕上反复点，风险大于收益）。

---

## 4. 九条主线改动（A–I）

### A. 固定签名身份，让重打包不再丢 TCC 授权

**现象**：新打出来的包有时丢授权；点设置里任一权限项会闪退；不闪退时系统设置里会出现「将 SaiShot 拖到上方列表」的横条。
**根因**：ad-hoc 签名把 designated requirement 绑在 cdhash 上，每次重建哈希都变，TCC 记录对不上。
**做法**：
- `openssl` 生成 10 年自签名证书，CN = `SaiShot Self-Signed`，SHA1 `4929ED3F3E7732ACAC354D7755D3692CB694D70E`
- p12 存 `~/SaiShot-signing/SaiShot-signing.p12`（口令 `SaiShot`）
- 导入独立钥匙串 `~/Library/Keychains/saishot-signing.keychain-db`（**密码是 `SaiShot`，不是开机密码**——用户曾误输开机密码导致弹窗反复失败）
- `security add-trusted-cert -r trustRoot` + `security set-key-partition-list` 让 codesign 静默使用私钥
- `scripts/bundle.sh` 增加 `SIGN_IDENTITY` / `SIGN_KEYCHAIN` / `SIGN_KEYCHAIN_PASS`（默认即上述值），签名前 unlock + set-key-partition-list，签名失败 `exit 1`
**坑**：`security import` 报 `MAC verification failed` → 必须用 `-keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1` 重新导出 p12。
**说明**：`spctl -a -t exec` 仍显示 rejected（自签名未公证），本机自用不影响。

### B. 窗口钉图向右上「跳一下」

**现象**：截图对象是**某个窗口**时，点钉子一瞬间贴图往左上/右上跳；框选区域截图不跳。
**双层根因**：
1. `PinLauncher.pin(image:at:)` 把「含阴影 padding 的外扩图」左下角对齐到选区左下角 → 图像整体偏移
2. `makeKeyAndOrderFront` 触发 AppKit `constrainFrameRect`，把整帧压回可见区 → 二次偏移
**修法**：
- 新增 `EditWindowController.pinOriginAligningWindowContent(image:baseRect:)`：当 `isWindowCapture && windowShadowEnabled && !hasPreviewImage && !isBeautifyActive` 且图比选区大时，反扣 `padding.left / padding.bottom`
- 覆盖 `PinWindow.constrainFrameRect(_:to:)`，允许越界恰好一个 padding

### C. 窗口贴图进编辑器时变大 + 顶部多一条空白

**根因**：进编辑器时把「含 padding 的窗口框」当成 anchor/displaySize，而图已被 `transparentTrimmedImage` 裁成内容尺寸 → 按比例反铺，于是变大并把空白挤到上方。
**修法**：`pinContentFrame(inWindowFrame:)`、`pinFrame(anchoringContent:)`、`attachShadowIfNeeded()` 三个方法统一按内容尺寸换算。

### D. 编辑往返后贴图下方多一条半透明长条

**根因**：编辑往返后贴图从「投影烧在像素里」变成「缩成内容尺寸 + 子窗口 `PinShadowWindow` 自绘投影」，子窗口定位低了 33pt。
**修法**：进编辑前记录 `imageCarriesBakedShadow`；restore 时若 rendered 图没有透明留白，就用 `WindowEffects.withShadow(rendered, size: 44)` 重新把投影烧进像素。
**验证**：往返后帧完全一致 `(-28, 796, 638, 362)`，`shadowWin=false`，全屏只有一个贴图窗口。

### E. 贴图编辑态还能点钉子，复制出第二个贴图

**修法**：
- `EditWindowController.disablesPinAction`（init 默认 false）
- `OverlayWindowController` 构造编辑器时传 `disablesPinAction: onExitToPin != nil`
- `updateCaptureActionAvailability()` 对 `.pin` 调 `setEnabled(!disablesPinAction, for: .pin)`
- `performToolbarItem` 的 `case .pin:` 加 `guard !disablesPinAction`（P 键走同一路径）

### F. 快捷键精简 + 解放「双击 Command」

**用户诉求**：删掉「快捷键复制到剪贴板」；删掉双击 Command 复制；删掉快捷键页四个项目（复制到剪贴板 / 保存到文件 / 文字识别 / 录制）。

**核实出的四个反直觉事实（已当面纠正过用户认知）**：
1. 回车在改之前**完全没有绑定**（实测剪贴板仍是哨兵文本）
2. 双击 ⌘ 是 `clipboardHotkey` 的**默认值**（`currentClipboardHotkey()` 返回 nil 时走 `KeyMonitor` 650ms 连按检测），而且它还有第二用途——**没设截图热键时它就是默认截图触发键**
3. `KeyMonitor` 的 event tap 是 `.listenOnly`，**从不吞事件**，别的 App 一直收得到
4. 那个「点不了的叉号」其实能点，清空后退回显示默认文案「双击 ⌘」

**改法（删代码）**：
- `SettingsView.swift` −473 行：删 4 张卡 + 20 个方法 + 8 个 ivar + `cancelShortcutRecordings(except:)` 里 4 个 slot 分支 + `shortcutsResetClicked` / `updateLocalization` 8 处调用 + `shortcutClearClicked` 4 个 case
- `SettingsWindowController.swift` 2 行
- `HotkeyManager.swift` −21：删 `currentClipboardHotkey`、`currentClipboardDisplayString`、`eventMatchesClipboardHotkey`、`HotkeySlot.clipboard` 及冲突分支
- `Defaults.swift` −52：删 `clipboardHotkeyKeyCode/Modifiers`、`hasCustomClipboardHotkey`、`clearClipboardHotkey`、`migrateLegacySaveHotkeyIfNeeded`
- `EditorShortcutRegistry.swift`：把 `.confirm` 固定为 `kVK_Return / 0`
- `OverlayWindowController.swift`：热键匹配换成 `keyCode 36/76 && editController?.isTextEditing != true → confirmFromKeyboard()`
- `AppDelegate.swift`：双击 ⌘ 只保留「默认截图触发」，浮层已经开着时改 `triggerContext.finish(.ignored)`

**事故记录**：测试时误把用户的 ⌘1 截图热键清掉了，已用 `defaults write screenshotHotkeyKeyCode=18 / screenshotHotkeyModifiers=256` 写回并重启验证。

**现状（快捷键页只剩 4 行）**：截图（⌘1）、取色器（未设置）、复制图中文字（⌘2）、截图翻译（未设置）。

### G. 贴图工具栏加「保存」+ 贴图编辑态隐藏侧工具栏

- `PinToolbarView` 从 edit / copy / zoom 三元素扩到四元素，新增 `saveButton`（`square.and.arrow.down`）、`onSave`、`saveTapped`
- 新方法 `PinLauncher.savePinnedImage()`：`ImageOutputEncoder.encodeAsync(quality: .original)` → `FilenameTemplate.imageFileName` → `SaveDestination.uniqueFile(Defaults.screenshotSaveDirectory)` → `ToastWindow.show(L10n.screenshotSaved(to:))`
- **踩坑**：`preferredWidth` 先设 136，实测 136 < `requiredWidth(3) = 140`（6*2 + 3*24 + 4*4 + 40），`layout()` 的自动收起逻辑把**最左的铅笔按钮**隐藏了；改成 **158** 后四个元素齐全
- 侧工具栏：`showToolbar()` 里 `if !layout.side.isEmpty` → `if !layout.side.isEmpty, !disablesPinAction`（贴图编辑态整条不建，不是禁用）
- 单测同步更新：`testPinToolbarProvidesEditAndCopyOnly` → `testPinToolbarProvidesEditCopyAndSave`；`testPinToolbarHidesOptionalButtonsFromLeftToRight` 阈值 191 / 90 / 60

### H. 合并回主工程（执行过，后被放弃）

曾把 Junior 的 15 个文件覆盖进 `SaiShot_1109`（两份 Localizable.strings、PinLauncher、OverlayWindowController、EditWindowController、EditorShortcutRegistry、SettingsView、SettingsWindowController、HotkeyManager、Defaults、Localizer、PinWindowInteractionTests、PermissionFlowLocalizer、bundle.sh、AppDelegate），并回改两处身份（URL scheme 改回 `saishot`、`APP_NAME` 改回 `SaiShot`）；`Info.plist` 与 `HistoryManager` 未合。

结果：`SaiShot_1109` 构建通过、出包 `build/SaiShot.app`、签名 root 一致、`swift test` 194 例 5 失败（既有）。但用户随后判断「合并要在屏幕上反复点，风险大于收益」，决定**放弃合并，Junior 作为唯一版本**。这一步的价值仅在于：合并路径已被验证可行，若将来需要，可按上述 15 文件清单重做。

### I. 改名 SaiShotJunior 收尾 + 打包不再丢授权（历史阶段）

用户手工把 `SaiShot_副本` 改名 `SaiShotJunior` 之后：

1. `rm -rf .build`（协变目录必须清，否则报 `PCH was compiled with module cache path` / `missing required module 'SwiftShims'`）→ `swift build` 干净通过
2. 重出包 → `codesign --verify --deep --strict` 通过，DR 不变
3. **打包脚本改造（关键）**：原来 `commit` 里第 74 行是 `rm -rf "$APP_DIR"`——每次出包把整个 `.app` 删掉重建，macOS 一旦发现它记住的 App 消失了，就把 TCC 记录一起清掉。现在改成：
   - 先组装到 `build/.staging/SaiShot.app`
   - 用 `rsync -a --delete` 把内容**覆盖进**已有的 `build/SaiShot.app`（**bundle 根不删**）
   - 在最终路径上签名，`.staging` 用完即删
   - 另提供 `--install` / `INSTALL_AFTER_BUILD=1` / `INSTALL_DIR`，把同一套「就地覆盖、不删根」逻辑用于安装到任意目录
4. 用户最终决定**不要 `/Applications` 那份**（App 还在实验阶段）。实测：删掉 `/Applications/SaiShot.app` 不影响 `build/` 那份的授权；随后连续两轮「就地重打包 → 重启进程 → ⌘1 框选 → 回车」都正常拿到 366 KB PNG，授权一次没掉。

**结论性经验**：TCC 记录怕的是「App bundle 消失」，不怕「内容被覆盖」。所以任何重打包/更新都要保住 bundle 根目录。

---

## 5. 代码地图（接手先看这几处）

| 文件 | 关键符号 | 管什么 |
|---|---|---|
| `SaiShot/Capture/PinLauncher.swift` | `PinShadowWindow`、`PinShadowView`、`makeShadowWindow`、`attachShadowIfNeeded()`、`pinContentFrame(inWindowFrame:)`、`pinFrame(anchoringContent:)`、`hasTransparentEdgePadding(_:)`、`imageCarriesBakedShadow`、`transparentTrimmedImage`、`copyPinnedImage()`、`savePinnedImage()`；`PinWindow.constrainFrameRect(_:to:)` 覆盖；`PinToolbarView`（约 2518 行起，`preferredWidth 158`、`iconButtonSide 24`、`zoomMinimumWidth 40`、`horizontalInset 6`、`itemGap 4`、`requiredWidth(3) = 140`） | 贴图窗口、投影、工具栏、保存/复制 |
| `SaiShot/Editor/EditWindowController.swift` | `disablesPinAction`、`pinOriginAligningWindowContent(image:baseRect:)`、`showToolbar()` 内 `if !layout.side.isEmpty, !disablesPinAction`、`updateCaptureActionAvailability()`、`performToolbarItem` 的 `case .pin: guard !disablesPinAction` | 编辑窗口、侧工具栏、钉图动作开关 |
| `SaiShot/Capture/OverlayWindowController.swift` | `exitEditorToPin()`、`onExitToPin`、空格 49 / Esc 53、`EditWindowController(... isWindowCapture:, disablesPinAction: onExitToPin != nil, ...)`（约 1984 行）、回车确认 `keyCode 36/76` | 截图浮层、进出编辑器的状态机 |
| `SaiShot/Editor/EditorShortcutRegistry.swift` | `.confirm → EditorShortcutBinding(keyCode: UInt32(kVK_Return), modifiers: 0)` | 编辑器快捷键表 |
| `SaiShot/Settings/SettingsView.swift` | 快捷键页 4 行（截图 / 取色器 / 复制图中文字 / 截图翻译） | 设置界面 |
| `SaiShot/Trigger/HotkeyManager.swift` | 已删 clipboard slot 相关全部逻辑 | 全局热键注册 |
| `SaiShot/Utilities/Defaults.swift` | 新增 `static var pinToolbarSave: String`（约 166 行，紧跟 `pinToolbarEdit`）；已删 clipboardHotkey 五个属性 | UserDefaults 封装 |
| `SaiShot/Utilities/Localizer.swift` | `appDisplayName`、`branded()`（主工程里是恒等变换） | 文案品牌化 |
| `ThirdParty/PermissionFlow/Sources/PermissionFlow/PermissionFlowLocalizer.swift` | `resourcesBundle`（5 个候选路径，全 miss 才回落 `Bundle.module`） | 授权面板文案 |
| `Resources/zh-Hans.lproj/Localizable.strings` / `Resources/en.lproj/Localizable.strings` | `"pinToolbarSave"` = 保存钉图 / Save pinned image | 本地化 |
| `scripts/bundle.sh` | `APP_NAME`/`APP_EXECUTABLE`、`SIGN_IDENTITY`/`SIGN_KEYCHAIN`/`SIGN_KEYCHAIN_PASS`、`STAGE_DIR`、`install_app()`、`--install` / `INSTALL_AFTER_BUILD` / `INSTALL_DIR` | 出包 + 签名 + 安装 |
| `Tests/SaiShotTests/PinWindowInteractionTests.swift` | 两个工具栏用例已按「三按钮/四元素」更新 | 回归测试 |

---

## 6. 构建 / 运行 / 测试

```bash
cd /Users/sai/Documents/GitHub/Sai_apps/SaiShot
bash scripts/bundle.sh                # 出包：build/SaiShot.app（就地覆盖，不动授权）
open build/SaiShot.app          # 运行（当前唯一的运行副本）
codesign -d -r- build/SaiShot.app   # 核对 DR
codesign --verify --deep --strict build/SaiShot.app
```

- 目录/工程改名后**必须先 `rm -rf .build`**，否则模块缓存路径失配
- 出包后如果 `.app` 根目录出现多余文件会报 `unsealed contents present in the bundle root`（历史上是因为往包里塞了额外文件）
- `swift test`：**历史基线 194 例 / 5 失败**，全部在 `Tests/SaiShotTests/OverlayPresentationTests.swift`：
  - `testCaptureStartsWithCrosshairAndPointerEventsKeepIt`（L375）
  - `testExistingSelectionAdjustmentDoesNotRestoreMagnifier`（L617）
  - `testFShortcutTogglesMagnifierColorFormat`（L327）
  - `testOverlayIsInteractiveBeforeTwoSecondPreparationFinishes`（L191）
  - `testRShortcutIsHandledWhileSnapshotPreparationIsPending`（L288）
  （多为 `SelectionView` 解包 nil 或 0≠1，属既有问题，**不是本轮回修改引入**。判断标准：失败数不增加即视为通过）
- ⚠️ 交接时 `swift test` 跑不起来，报 `input file ... was modified during the build`——因为另一个进程正在改源码（见第 11 节）。复跑前应先确认无人并发编辑。

---

## 7. 坑与死路（省时间的清单）

1. 只 `rm -rf build/…app` 或包内删根 → TCC 授权必掉；`rsync` 就地覆盖不掉。
2. 两个同 bundle id 的副本同时运行（`build/` 与 `/Applications`）→ 热键互抢、权限状态读数错乱，曾导致误判「授权丢了」。
3. `preferredWidth` 小于 `requiredWidth(n)` 会被自动收起逻辑从**左边**开始吞按钮。
4. `spctl -a -t exec` 对自签名包永远是 rejected，别当成问题。
5. 自签名钥匙串密码是 `SaiShot`，**不是开机密码**。
6. `osascript ... click menu item "截图"` 偶发 `missing value`，重试即可；菜单名可能是 `menu SaiShot of menu bar item 1`。
7. `pkill` 偶发 `Cannot get process list`（系统权限/环境噪声），改用 `osascript -e 'tell application "SaiShot" to quit'`。
8. 部分截图 `Read` 报 `RESOURCE_UPLOAD_UNKNOWN_ERROR`，换缩放尺寸（900/1000 px）重读。
9. 改系统设置里的权限开关会弹 Touch ID，Agent 无法代做。
10. GUI App 里用 `print` 调布局数值看不到 stdout（`open` 启动无终端）→ 写文件再读（如 `/tmp/pin_dbg.txt`）。
11. `PinToolbarView` 里 `pinWindow` / `image` 在该作用域是非可选，写 `?.` 会编译失败。

---

## 8. 用户决策与边界（另一个 AI 务必遵守）

**已确认接受**
- 固定自签名身份，保住 TCC
- 所有改动先在 Junior 验证
- **放弃合并**，Junior 是唯一最终版本，原 SaiShot 不要了
- 历史截图不要了；两套设置无所谓
- `SaiShot_1109` 由用户自行归档，别人不要动
- 目录已改名 `SaiShot`（2026-11-11 从 `SaiShotJunior` 全量改回）
- **App 只留在 `build/`，不进 `/Applications`**（还在实验阶段）

**已执行（2026-11-11）**
- 把显示名从 `SaiShotJunior` 改成 `SaiShot`，bundle id 改为 `cn.skyrin.saishot`，URL scheme 改为 `saishot://`
- 工程目录重命名为 `SaiShot`
- 结束后需重新授权屏幕录制 / 辅助功能 / 麦克风

**已拒绝 / 不需要**
- 发布说明文件、归档到 `~/Pictures/PicBed-Archive`、`--retry-failed`/`--where` 子命令、PicGo 之外自动化接管、`xattr com.capcap.*` 迁移
- 用户在屏幕上反复点操作来「合并两个工程」

**偏好**
- 只改显示名、不动 bundle id（否则又是新 App、又掉授权）
- 不要在没有验证的情况下交付；交付前必须自测（含交互流程与回归）
- 调试要有详尽日志，但不要陷入无效调试循环；宁可给完整可执行方案

---

## 9. 未完成 / 待决策

| 项 | 状态 |
|---|---|
| 显示名 / bundle id / URL scheme 全量改为 `SaiShot` | 2026-11-11 已完成；权限需重新授权 |
| URL scheme `saishot://` | 已生效 |
| 5 个既有测试失败（OverlayPresentationTests） | 长期存在，未修；用户未要求 |
| `SaiShot_1109` 归档 | 用户自理，Agent 未参与 |
| 是否提交 git | 未做，工作区一直悬着 `+52x/−62x` 改动 |

---

## 10. 调试工具箱（历史上一直都在，可能被清掉）

| 工具 | 用途 |
|---|---|
| `/tmp/events2` | `move x y` / `click x y` / `key <code> [shift\|cmd]`（CGEvent 注入） |
| `/tmp/events` | `drag x y dx dy` / `scroll x y amount` / `click x y` |
| `/tmp/wl.swift` | 枚举窗口 id 与 bounds（`swift /tmp/wl.swift`） |
| `/tmp/cmd2` | 模拟双击 Command |
| `screencapture -R x,y,w,h -x out.png` | 定点区域截图（比全屏截图后裁剪更可靠） |
| `sips -Z 900 out.png --out out_s.png` | 缩放后再 `Read`，避免上传失败 |

注意事项：窗口不在当前 Space 时单窗截图易 `SCREENSHOT_WINDOW_NOT_VISIBLE`；全屏截图后裁剪更稳。

---

## 11. 交接时的工作区状态提醒

写这份文档时（2026-11-10 12:42–12:45），工程里有**另一个进程正在实时修改源码**：

- `SaiShot/Utilities/CrashLogReader.swift`（`processName` → `processNames` 数组匹配，12:43:16 写入）
- `SaiShot/Capture/HistoryManager.swift`（12:43:10）
- `SaiShot/Utilities/SaveDestination.swift`（12:44 之后仍被改写）
- `scripts/rebuild-and-open.sh`（12:42:50，改成 `INSTALL_DIR=/Applications` + `bash scripts/bundle.sh --install`）

后果：`swift build` / `swift test` 会报 `input file ... was modified during the build`。

接手建议：
1. 动手前先 `git status` + `git diff --stat` 拍一张快照，确认没有并发写入
2. **注意 `scripts/rebuild-and-open.sh` 当前默认装到 `/Applications`**，与用户「只用 build 那份」的最新决定冲突；若被误执行，会重新造出一份 `/Applications` 副本（同 bundle id），又可能出现双实例争热键的老问题
3. 不要一次性 `git checkout .` 或 `git stash` 抹掉工作区——那 +52x/−62x 就是全部改动成果，没有提交可回滚
