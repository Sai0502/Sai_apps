# Saladict 桌面版（个人精简版）

基于 Tauri 1.x + React + Vite 的划词翻译桌面应用，只保留 macOS 和 Windows，供个人使用。

## 功能

- 划词翻译：选中文本后点击悬浮图标，或使用全局快捷键。
- 钉住即译：将翻译窗口钉住后，划选任意文本会立即翻译，不需要再点图标，也不会抢走当前应用的焦点。
- 输入翻译、截图 OCR、截图翻译。
- 多翻译服务并行、多 OCR 服务、TTS、生词本。
- 剪贴板监听、托盘菜单、全局快捷键、插件系统。

## 精简说明

当前版本只为个人使用维护，已移除：

- Linux 平台代码和配置
- App Store / 360 商店相关配置
- 自动更新、启动检查更新、远程通知
- GitHub Actions、发布脚本、对外说明文档和商店素材
- 构建缓存和依赖目录

`LICENSE` 保留，用于满足 GPL 许可要求。项目不发布、不售卖。

## 目录结构

```text
.
├── Saladict.app              # 已构建的 macOS 应用（Apple Silicon）
├── index.html                # 前端入口
├── daemon.html               # 后台窗口
├── public/                   # 前端静态资源
├── src/                      # React 前端
│   ├── window/               # 各类窗口：Translate / Recognize / Screenshot / Config / Thumb
│   ├── services/             # 翻译、OCR、TTS、生词本服务
│   ├── hooks/                # 通用 hooks
│   ├── utils/                # 工具函数
│   └── i18n/                 # 多语言
├── src-tauri/                # Rust 后端
│   ├── src/                  # Tauri 命令、窗口、鼠标钩子、快捷键等
│   ├── resources/            # macOS OCR 可执行文件
│   ├── icons/                # 应用图标
│   ├── Cargo.toml
│   └── tauri*.conf.json
├── package.json
└── pnpm-lock.yaml
```

## 环境要求

### macOS

- Node.js + pnpm
- Rust stable（rustup）
- Xcode Command Line Tools

### Windows

- Node.js + pnpm
- Rust stable（MSVC 工具链）
- Visual Studio Build Tools，勾选「使用 C++ 的桌面开发」和 Windows SDK
- WebView2（安装包已配置为自动嵌入）

> Windows 安装包必须在 Windows 上构建，Tauri 1.x 不支持在 macOS 上交叉编译 Windows 安装包。

## 安装依赖

```bash
pnpm install
```

## 开发

```bash
# 只启动前端
pnpm dev

# 启动 Tauri 桌面开发模式
pnpm tauri dev
```

## 构建

### macOS

```bash
pnpm build:mac
```

产物会自动复制到项目根目录：

```text
./Saladict.app
```

仓库中现有的 `Saladict.app` 是 Apple Silicon（arm64）版本。如果是 Intel Mac，需要换成对应目标重新构建。

### Windows

在 Windows 电脑的项目目录执行：

```bash
pnpm build:win
```

命令会执行 NSIS 打包，并把安装包复制到项目根目录。也可以手动到下面的目录查找：

```text
src-tauri\target\release\bundle\nsis\
```

## 使用

1. 打开 `Saladict.app`（或 Windows 安装后的应用）。
2. macOS 首次使用需要在「系统设置 → 隐私与安全性 → 辅助功能」中授权本应用。
3. 在设置中配置至少一个翻译服务。
4. 划词后点击悬浮图标，或使用划词翻译快捷键，打开翻译窗口。
5. 点击翻译窗口右上角的钉子，进入「钉住即译」模式；之后直接划选文本即可翻译。
6. 再次点击钉子退出该模式。

## 配置与数据

配置标识符：`allen.town.focus.saladict`

- macOS：`~/Library/Application Support/allen.town.focus.saladict/`
- Windows：`%APPDATA%\allen.town.focus.saladict\`

## 常见问题

**macOS 提示无法打开应用**

应用为本地 ad-hoc 签名。可以右键点击 `Saladict.app` 选择「打开」，或执行：

```bash
xattr -dr com.apple.quarantine Saladict.app
```

**划词没有反应**

确认已授予「辅助功能」权限；修改权限后需要重启应用。

**Windows 构建失败**

确认已安装 Visual Studio C++ 桌面开发组件、Windows SDK 和 Rust MSVC 工具链。

**翻译失败**

检查对应翻译服务的 API Key、网络和代理设置。

## 关于构建缓存

Rust/Tauri 默认会把构建缓存放在 `src-tauri/target/`，体积可能达到数 GB。构建脚本只会把最终 APP 或安装包复制到项目根目录，`target/` 可以随时删除。

## 许可

见 `LICENSE`。仅个人使用，不对外发布或销售。
