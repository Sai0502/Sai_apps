# Swiss Knife —— 四合一融合需求说明

> 版本：v1.1（2026-10-11）· 状态：核心决策已确认
> 一句话诉求：**把 FlowClone、NetWork-WatchDog、ATASWheelTamer、FitRecordZone 四个独立的菜单栏 App 融合成一个 App（Swiss Knife），顶部状态栏只保留一个状态位（NetWork-WatchDog 的状态图标 + FlowClone 的倒计时），不新增任何功能，仅对合并后的菜单做删减。**

---

## 〇、已确认决策（2026-10-11 用户拍板）

| 决策点 | 结论 |
|---|---|
| 应用名 | **Swiss Knife** |
| 状态栏样式 | **emoji + 倒计时并排**（如 🟢 24:53：左=网络状态图标随网络/USB 状态变 🟢🔴❌，右=FlowClone 番茄钟倒计时） |
| 启动方式 | **四个模块全部随 App 启动自动运行**（同现在各自常驻） |
| 设置窗组织 | **保留 FlowClone 原 4 tab（常规/时长/通知与声音/附加功能）+ 新增第 5 个 tab「工具」**（放网络 WiFi、滚轮倍率、取景框配置） |

---

## 一、四个 App 现状（融合的原料）

| App | 技术栈 | 状态栏显示 | 点开菜单 | 设置形态 | 核心功能 |
|---|---|---|---|---|---|
| **FlowClone**（番茄钟） | SwiftUI · 脚本构建 .app | 图标 + 阶段剩余倒计时（如 `24:53`） | 进行中·Flow·倒计时 / 暂停 / 跳过 / 停止 / 设置 / 复制调试信息 / 退出 Flow | **完整设置窗**：4 个 tab（常规 / 时长 / 通知与声音 / 附加功能） | 番茄钟计时（Flow / 短休 / 长休）、提示音、全屏休息、定时播放（5 行 × 时间/音视频/图片 + 星期生效） |
| **NetWork-WatchDog**（网络看门狗） | AppKit · SwiftPM → .app | 状态 emoji：🟢 / 🔴 / ❌（网络 + iPhone USB 共享状态） | 标题（含时间戳）/ iPhone USB 状态 / 可用 WiFi：Sai（点开改 WiFi 名密码）/ Logs / Open Log Folder / Quit | 无设置窗；WiFi 名/密码在菜单对话框里改 | 每 1 秒检查网络与 iPhone USB 共享，断线自动恢复（重连 WiFi / 切换 USB），系统通知，日志写到桌面「自动联网日志」 |
| **ATASWheelTamer**（滚轮倍率调节） | AppKit · SwiftPM → .app | 文字 `AW` | Atas 缩放倍率（启用/禁用 + 缩放比例子菜单）/ Parallels 缩放倍率（同）/ 重新挂载拦截 / 复制最近日志 / 复制调试快照 / 打开日志目录 / 退出 | 无设置窗；菜单直接操作 | 拦截全局滚轮事件（CGEventTap，需辅助功能授权），对 ATAS 交易软件与 Parallels 虚拟机分别按倍率缩放滚轮（0.5%–100%，可自定义一位小数），0.5 秒刷新 |
| **FitRecordZone**（取景框） | AppKit · SwiftPM → .app | 文字 `FR` / `FR*`（有星号 = 取景框显示中） | 显示 / 设置边框颜色… / 复制最近日志 / 复制调试快照 / 打开日志目录 / 退出 | 无设置窗；菜单直接操作 | 屏幕上显示按比例（16:9 / 9:16 / 1:1…）的取景边框，可调边框颜色，用于拍摄构图参考 |

**共同点**：全部是无 Dock 图标的菜单栏应用（LSUIElement），启动即常驻状态栏；日志机制相近（复制最近日志 / 复制调试快照 / 打开日志目录）；各自的 UserDefaults 键互不冲突（FlowClone 用 `local.flowclone.app`，另外三个各用各的 bundle id / defaults）。

---

## 二、融合后的形态（我的理解）

### 1. 状态栏（顶部）
- **一个状态位**：左边是 **NetWork-WatchDog 的状态图标**（🟢 / 🔴 / ❌，随网络/USB 状态实时变化），右边是 **FlowClone 的倒计时**（如 `24:53`，随番茄钟阶段显示剩余时间）。
- 点击这一格展开**整合菜单**。

### 2. 整合菜单（点开状态栏）
按 4 个模块分组展示（对齐用户最终拍板的版式）：

```
Swiss Knife                        ← 加粗大字号
────────────────────
Flow · 进行中 · 24:58              ← 名称 · 状态 · 倒计时
    暂停
    跳过                          （删掉「停止」；待机时第二行变「开始」、跳过置灰）
────────────────────
NetWork-WatchDog · Online          ← 名称 · 状态
    Logs                          （删掉「可用 WiFi」「Open Log Folder」）
────────────────────
ATAS Wheel Tamer
    重新挂载拦截
    ✅ Atas 缩放倍率：1%
        启用 / 禁用              （比倍率行再缩进一级）
        缩放比例
    ❌ Parallels 缩放倍率：2%
        启用 / 禁用              （比倍率行再缩进一级）
        缩放比例
────────────────────
FitRecordZone
    显示
    设置边框颜色…
────────────────────
复制调试快照（四合一）
设置
退出 Swiss Knife
```

> 说明：✅/❌ 前缀保留（一眼区分启用状态）；子项统一 4 空格缩进、倍率行下的操作再缩进一级（8 空格）；「复制调试快照」顶格，点击复制四个模块全部调试信息（供出 bug 时排查）。

### 3. 设置
- 保留 FlowClone 的完整设置窗（4 个 tab 原样），**在其上增加工具模块的设置分区**（网络看门狗的 WiFi 名/密码、滚轮倍率、取景框比例/颜色等低频配置收进设置窗）。
- ATAS / Fit 目前没有设置窗，它们在菜单里的高频操作（启用/禁用、缩放比例、显示、边框颜色）**保留在菜单里**，不搬走。

### 4. 菜单删减清单（重复项合并，不新增功能）
| 原分散在各 App | 融合后 |
|---|---|
| 「退出 Flow」「Quit」「退出」×3 → 共 4 处 | **只保留 1 个「退出」** |
| 「复制调试信息」（Flow）/「复制调试快照」（ATAS、Fit） | 合并为 **1 个「复制调试快照」**（汇总四个模块的状态） |
| 「复制最近日志」（ATAS、Fit）+「Logs」（WatchDog） | 合并为 **1 项**（打开统一日志或复制最近日志） |
| 「打开日志目录」（ATAS、Fit）/「Open Log Folder」（WatchDog） | 合并为 **1 个** |
| 各菜单顶部的模块标题行 | 统一为一个标题（应用名） |
| WatchDog 状态标题里的时间戳（MMddHHmm） | 删掉（倒计时已承担时间展示） |
| 四个 App 各自的图标位 | 合并为**一个状态位** |

---

## 三、技术要点（实现阶段的预案）

1. **代码组织**：新建 `SwissKnife` 项目，把四个项目的源码合并进来。因三个 AppKit 项目都是零依赖、纯 Swift，合并成本低；FlowClone 是 SwiftUI，混合架构可行（AppKit 菜单栏 + SwiftUI 设置窗）。
2. **符号冲突**：ATAS 与 Fit 都有 `AppDelegate`、`SettingsStore`、`DebugLogger`，合并时需改名为各自前缀（如 `WheelTamerStore` / `ZoneStore`）或以模块/Target 隔离。
3. **日志统一**：建议统一到一个日志目录，四模块各自记录日志行，调试快照汇总导出。
4. **权限**：ATAS 的辅助功能授权、WatchDog 的网络权限在合并后照常申请/保留。
5. **构建**：统一一个 `build.sh`，产物为单个 `SwissKnife.app`。

---

## 四、待你确认的问题

- ✅ **应用名**：Swiss Knife（已确认）
- ✅ **状态栏组合样式**：emoji（🟢/🔴/❌）+ 倒计时并排，倒计时格式沿用 Flow 原样（已确认）
- ✅ **四模块启动**：全部随 App 启动自动运行（已确认）
- ✅ **设置窗组织**：FlowClone 4 tab 保留 + 新增第 5 个 tab「工具」（已确认）
- ✅ **删减清单**：第二节第 4 点的删减表，如与你的预期不符，请指出要增删的项

---

## 五、实现状态（2026-10-11 晚，已全部落地并实机验证）

| 需求点 | 实现 | 验证 |
|---|---|---|
| 应用名 Swiss Knife | bundle `local.swissknife.app`，LSUIElement 无 Dock | 进程运行 ✓ |
| 状态栏一格：emoji + 倒计时 | `🟢/🔴/❌ + mm:ss`，1 秒刷新 | AX 实测 `Title=🟢 25:00` ✓ |
| 四模块随启动自启 | AppDelegate 启动 Flow/WatchDog/WheelTamer/Zone | 快照四模块都有数据 ✓ |
| 整合菜单（最终版式） | 加粗大字号标题；Flow(状态行/开始或暂停/跳过，无停止) + WatchDog(名称·状态/Logs) + ATAS Wheel Tamer(标题行 + 重新挂载拦截 + Atas/Parallels 倍率行，其下启用/禁用、缩放比例二级缩进) + FitRecordZone(标题行 + 显示/设置边框颜色) + 复制调试快照/设置/退出 Swiss Knife | AX 实测 30 项结构完整 ✓ |
| 复制调试快照四合一 | 汇总 Flow/WatchDog/WheelTamer/Zone 全状态 | pbpaste 实测四段齐全 ✓ |
| WatchDog 时间戳删除 | 状态标题仅 emoji 与文案，无时间戳 | ✓ |
| 设置窗 2 tab | **Flow**（合并原 常规+时长+通知与声音，删「自动行为」「菜单栏图标」；启动/时长/周期/通知/音量与滴答/完成提示音/专注）+ **附加功能**（定时播放原样）；「工具」tab 已删除 | AX 实测 2 RadioButton，Flow tab 各分组齐全 ✓ |
| 自动行为写死 | 自动开始 Flow / 自动开始休息 / 休息全屏 固定启用（引擎硬编码，设置项已移除） | 代码级 ✓ |

**已知事项**
- ATAS 滚轮拦截依赖辅助功能授权：首次运行如系统弹出授权框请允许；未授权时菜单显示「辅助功能授权: 未授权 / 事件拦截: 未运行」，需在 系统设置 → 隐私与安全性 → 辅助功能 中给 Swiss Knife 打勾后重启 App。
- 源码组织：`Sources/SwissKnife/{Flow,WatchDog,WheelTamer,Zone}/` 四子目录 + 根目录统一层（main/AppDelegate/MenuBarController）；构建 `export DEVELOPER_DIR=/Library/Developer/CommandLineTools && swift build -c release`，打包 `./build_app.sh`。
