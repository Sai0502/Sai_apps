# AGENTS.md

本文件用于指导在本仓库工作的 AI Agent。

## 项目定位

- 这是一个沙拉翻译（Saladict）桌面版的个人精简分支，**仅供个人使用，不发布、不售卖**。
- 只支持 **macOS + Windows**，不要重新引入 Linux 支持。
- 不要重新添加商店发布、CI、自动更新、远程通知、营销文档等外部内容，除非用户明确要求。
- 保持仓库精简：不要提交 `node_modules/`、`dist/`、`src-tauri/target/` 或构建出来的 APP。

## 技术栈

- 前端：React 19 + Vite 5 + Tailwind CSS + NextUI + jotai + i18next
- 后端：Tauri 1.8（Rust 2021）
- 包管理：pnpm
- 目标产物：macOS `.app`、Windows NSIS `.exe`

## 常用命令

```bash
pnpm install          # 安装前端依赖
pnpm dev              # 只启动 Vite 前端
pnpm tauri dev        # 启动 Tauri 开发模式
pnpm build            # 构建前端到 dist/
pnpm build:mac        # 构建 macOS APP 并复制到根目录 Saladict.app
pnpm build:win        # Windows 上构建 NSIS 安装包并复制到根目录
```

Rust 检查：

```bash
cd src-tauri
cargo check
```

### 已知问题

`pnpm lint` 目前会因为 `eslint.config.js` 引用了未声明的 `globals` 包而失败。这是原项目遗留问题；验证代码时优先使用：

```bash
pnpm build
cd src-tauri && cargo check
```

## 构建产物约定

- macOS 最终产物：项目根目录 `Saladict.app`
- Windows 最终产物：项目根目录的 NSIS `.exe`
- `src-tauri/target/` 只是 Cargo/Tauri 缓存，构建完成后可以删除。
- `pnpm build:mac` 已经包含「构建 + 复制到根目录」的步骤，不需要再手动进入深层目录找 APP。
- Windows 安装包不能从 macOS 交叉编译，必须在 Windows 上构建。

## 代码结构

### 前端

- `src/App.jsx`：根据 Tauri 窗口 label 选择渲染对应窗口。
- `src/window/Translate/`：翻译窗口。
- `src/window/Recognize/`：OCR 识别窗口。
- `src/window/Screenshot/`：截图窗口。
- `src/window/Config/`：设置窗口。
- `src/window/Thumb/`：划词后显示的小图标窗口。
- `src/services/`：翻译、OCR、TTS、生词本服务实现。
- `src/hooks/`：`useConfig` 等通用 hooks。
- `src/utils/`：工具函数、store、语言检测等。
- `src/i18n/`：多语言资源。

### Rust 后端

- `src-tauri/src/main.rs`：应用入口、Tauri 命令注册、启动初始化。
- `src-tauri/src/window.rs`：窗口创建、翻译窗口、缩略图标窗口、焦点控制。
- `src-tauri/src/mouse_hook.rs`：全局鼠标钩子、划词检测、钉住即译状态。
- `src-tauri/src/hotkey.rs`：全局快捷键。
- `src-tauri/src/clipboard.rs`：剪贴板监听。
- `src-tauri/src/tray.rs`：托盘菜单。
- `src-tauri/src/config.rs`：本地配置存储。
- `src-tauri/src/system_ocr.rs`：macOS / Windows 系统 OCR。
- `src-tauri/src/utils.rs`：选中文本、键盘模拟、权限等平台工具。
- `src-tauri/src/backup.rs`：WebDAV / 阿里云备份。
- `src-tauri/src/server.rs`：本地 HTTP 外部调用接口。

## 钉住即译流程（重要）

1. `src/window/Translate/index.jsx` 中点击钉子时调用 Tauri 命令 `set_translate_pinned`。
2. `src-tauri/src/mouse_hook.rs` 用 `AtomicBool` 保存钉住状态：
   - `is_translate_pinned()`：读取状态。
   - `set_translate_pinned()`：前端命令入口。
   - 鼠标命中划词且已钉住时，直接调用 `window::text_translate_no_focus()`。
3. `src-tauri/src/window.rs`：
   - `translate_window_with_focus(false)`：更新已有窗口时不抢焦点。
   - `text_translate_no_focus()`：写入文本并发出 `new_text_no_focus` 事件。
4. `src/window/Translate/components/SourceArea/index.jsx` 监听 `new_text_no_focus`，更新内容但不调用 `appWindow.setFocus()`。
5. `src-tauri/src/main.rs` 在翻译窗口销毁时调用 `set_pinned_state(false)`，避免状态残留。

修改这部分时注意：

- 不要在钉住模式下抢焦点，否则连续划词会被打断。
- 不要重新弹出小图标；钉住模式下应直接翻译。
- 鼠标事件落在翻译窗口内部时应忽略，避免在面板内选词导致重复翻译。
- macOS 需要辅助功能权限，否则鼠标钩子不会启动。

## 平台约束

- 只保留 `macOS` 和 `Windows` 的 `cfg` 分支。
- 已移除所有 Linux 分支、Linux 配置、Wayland/Hyprland 补丁和 Linux 依赖。
- Windows 专用代码位于：
  - `src-tauri/src/system_ocr.rs` 的 `cfg(target_os = "windows")`
  - `src-tauri/src/cmd.rs`、`utils.rs`、`window.rs` 中的 Windows 分支
  - `src-tauri/tauri.windows.conf.json`
  - `Cargo.toml` 的 `[target.'cfg(windows)'.dependencies]`
- macOS 专用代码位于对应的 `cfg(target_os = "macos")` 分支和 `tauri.macos.conf.json`。
- 不要删除这些 Windows 分支，否则 Windows 构建会失败。

## 配置约定

- 构建目标：`src-tauri/tauri.conf.json` 中为 `["app", "nsis"]`。
- 应用标识符：`allen.town.focus.saladict`。
- 托盘、窗口、图标分别由 `tauri.macos.conf.json` 和 `tauri.windows.conf.json` 覆盖。
- 自动更新和远程通知已移除；不要重新添加依赖外部服务的启动逻辑。

## 代码风格

- 前端使用 4 空格缩进、单引号、现有 NextUI/Tailwind 组件风格。
- 不要添加无意义注释；只在逻辑不直观时添加简短注释。
- 遵循现有文件组织方式，不要随意引入新框架或新依赖。
- 修改后至少运行：
  - `pnpm build`
  - `cd src-tauri && cargo check`
  - macOS 产物验证：`pnpm build:mac`

## 不要做的事

- 不要重新添加 Linux 支持。
- 不要重新添加 App Store、360、自动更新、远程通知、GitHub Actions、发布脚本。
- 不要删除 `LICENSE`。
- 不要把 `node_modules/`、`dist/`、`src-tauri/target/` 或用户的配置/数据提交进仓库。
- 不要在没有明确要求的情况下大改翻译服务列表或删除用户可能使用的服务。
