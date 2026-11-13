# AGENTS.md — Sai_apps 仓库总规

本文件是这个仓库（多个独立个人项目共存的上一级目录）的**总规则**。
`clean_for_upload.sh`、`.gitignore`、各子项目的 `AGENTS.md` 都以本文件为准。

子项目有自己的 `AGENTS.md` 时，**子项目的规则优先**；本文件只兜底子项目没写到的部分。

> 项目清单：SaiDict、SaiPaste、SaiShot、SwissKnife、Chrome_Extension、TTS、
> Python Scripts、iOS-DailyToDo、iOS-WorkoutToDo、TV 指标。

---

## 0. 最高优先级：代码不可再生，产物可以重造

这三条压倒其它一切规则，任何工具、脚本、agent 都不得违反：

1. **手写源码永远不删。** 删了不能靠重新构建恢复。
2. **成品可以重造。** `.app`/`.dmg`/`.exe` 之类的成品即使误删，重新 `build` 即可，
   所以宁可保护多余一点，也不要冒删掉源码的风险。
3. **不确定就保留并报告。** 任何"看起来像构建产物但认不准"的目录，
   一律保留、在输出里列出路径，由人来决定。静默删除是禁止行为。

判断顺序（凡是要删东西的工具都照这个顺序做）：

```
是不是 .git / 成品 → 保留
是不是已知生成目录（target/debug、.build、node_modules…）→ 可以删
是不是含工程标志文件（Cargo.toml、Package.swift、*.xcodeproj…）→ 保留
是不是含源码文件 → 保留
否则 → 可以删
```

---

## 1. 目录约定：成品放项目根，构建缓存放固定位置

这是本仓库的**硬约定**。新项目也照这个来，清理脚本才能安全地一律套用。

| 位置 | 性质 | 上传/清理时 |
|---|---|---|
| `<项目>/<项目名>.app` | 成品（最终交付物） | **保留** |
| `<项目>/.build/` | SwiftPM 编译缓存 | 可删 |
| `<项目>/src-tauri/target/` | Cargo/Tauri 编译缓存 | 可删（bundle 里的 .app 除外） |
| `<项目>/dist/` `build/` `out/` `target/` | 构建中间/输出 | 无成品时可删 |
| `<项目>/node_modules/` `.venv/` `Pods/` | 依赖缓存 | 可删 |
| `<项目>/Sources/` `src/` `src-tauri/src/` `Tests/` | **手写源码** | **绝对保留** |
| `<项目>/scripts/` `packaging/` `Resources/` `Support/` | 手写脚本与资源 | **绝对保留** |

### 新项目必须做到

- 成品复制/生成到**项目根目录**，不要只留在 `.build/` 或 `target/` 深处。
  这样即使整块缓存被清掉，成品也还在。
- 构建脚本里写完 `swift build` / `tauri build` 之后，
  紧跟一步"把产物 cp 到项目根"，和现有四个项目保持一致。
- **复制完之后把构建目录里的原始副本删掉**，避免同一份成品占两份空间。
  SaiDict 的 `build:mac` / `build:win` 已是这个写法：

  ```json
  "build:mac": "tauri build --bundles app && rm -rf SaiDict.app && cp -R src-tauri/target/release/bundle/macos/SaiDict.app ./SaiDict.app && rm -rf src-tauri/target/release/bundle/macos/SaiDict.app"
  ```

  删除范围**只限于成品副本本身**（`bundle/macos/*.app`、`bundle/nsis/*.exe`），
  不要连 `bundle/` 的父目录一起删——Cargo 的 `deps/`、`build/`、`incremental/`
  都在 `release/` 下，与 `bundle/` 平级，删错会废掉增量编译缓存。
- 构建缓存目录只放可再生成的东西，**不要往 `build/`、`target/` 里放手写代码**。
  确实需要把生成代码落盘时，让它落在 `target/`、`.build/` 这类已登记的路径下。

---

## 2. 清理脚本 `clean_for_upload.sh`

根目录的 `clean_for_upload.sh` 是唯一被授权做批量删除的工具。

```bash
bash clean_for_upload.sh              # 列出 + 询问 Y/N
bash clean_for_upload.sh --dry-run    # 只看，不删（改脚本后必须先跑这个）
bash clean_for_upload.sh --apply      # 直接删，自动化用
```

它的行为保证：

- 不删任何 `.git`、任何 `*.app` 及其内部、任何成品文件。
- `target/` 内含 `.app` 时**逐层下钻**，只保留成品所在的那一支，其余（`deps/`、`build/`、二进制）照删。
- 候选删除目录若含源码类文件或工程标志文件，**整个保留**并在报告里列出。
- 认不出性质的目录不删，只报告。

### 改这个脚本时的硬性要求

1. 改完先 `bash -n clean_for_upload.sh` 过语法，再 `--dry-run` 看输出是否合理。
2. 必须用隔离的合成项目验证过再上真实仓库（见第 5 节）。
3. **不许**新增"递归 rm -rf 一个可能含源码的目录"的路径。
4. **不许**把 `build`/`dist`/`target`/`out` 这种通用名直接当缓存删——
   必须过第 0 节那套判定顺序。

---

## 3. Git 与上传

- 本仓库根 `.gitignore` 管 Xcode/macOS 通用垃圾；子项目 `.gitignore` 管自己的产物。
- **不要提交**：`node_modules/`、`dist/`、`src-tauri/target/`、`.build/`、`DerivedData/`、
  任何 `*.app` / `*.dmg` / `*.pkg` / `*.exe`、签名证书 `*.p12`、`*.provisionprofile`。
- 目前 `SaiDict`、`SaiPaste`、`SaiShot`、`SwissKnife` 等目录**尚未被 git 跟踪**
  （`git status` 显示 `?? SaiDict/`）。这意味着"已提交即受保护"这条兜底对这些项目无效，
  清理脚本只能完全依赖第 0 节的文件类型判定。若以后决定纳入版本管理，先 `git add` 一次，
  保护会更稳。

---

## 4. 编码与项目风格

各子项目风格**以子项目 `AGENTS.md` 为准**，这里只写通用部分：

- 缩进/引号/命名跟随所在项目现有代码，不搞全仓库统一格式化。
- 不加无意义注释；只在逻辑不直观处写简短说明。
- 不随意引入新框架或新依赖；沿用各项目现有技术栈：
  - SaiDict：Tauri 1.8 + React 19 + Vite 5 + Tailwind + pnpm
  - SaiShot / SaiPaste / SwissKnife：纯 Swift + SwiftPM，无第三方依赖
  - Chrome_Extension：MV3 原生 JS
  - TTS / Python Scripts：Python 3
- 只支持 macOS + Windows，不重新引入 Linux 分支。

---

## 5. 验证习惯

- **改清理脚本** → 合成项目测一遍再跑真的（模板见下）。
- **改 iOS/Swift 项目** → 至少 `swift build` 通过。
- **改 SaiDict** → `pnpm build` + `cd src-tauri && cargo check`。
- **改 Chrome 扩展** → 手动在 Chrome 里重载确认。
- **改 Python** → 至少能 `python3 -m py_compile <file>` 通过。

合成项目验证模板（用来证明脚本不会误删源码）：

```bash
T=$(mktemp -d)
cp clean_for_upload.sh "$T/"
# 故意造最危险的情况：build/ 里同时有 .app 和手写源码
mkdir -p "$T/P/build/App.app/Contents" "$T/P/build/src"
echo bin > "$T/P/build/App.app/Contents/b"
echo 'switch x' > "$T/P/build/src/a.swift"
bash "$T/clean_for_upload.sh" --dry-run --no-pause
# 期望：App.app 保留、src 保留（含源码）、其余可删
```

### 已验证的对抗性场景（2026-11-14）

改完后用合成项目跑过下面六种情况，结果全部符合预期：

| 场景 | 期望 | 实际 |
|---|---|---|
| `build/` 内同时有 `.app` 和手写 `src/*.swift` | 两者都保留 | ✅ |
| `build/` 含 `.app`，同层另有一支 `MyLib/*.cs` | `.app` 与 `MyLib` 都保留 | ✅ |
| `target/release/` 有 `.app`、`deps/`、以及手写 `handwritten.rs` | `.app` 和 `.rs` 保留，`deps/` 删除 | ✅ |
| `dist/` 只有 `*.js` `*.css` `*.html` | 整目录删除 | ✅ |
| 名为 `build` 的文件夹只含 `model.ts` | 保留 | ✅ |
| SwiftPM `.build/` + 根 `.app` | `.build` 删除，`.app` 保留 | ✅ |

真实仓库执行结果（`--apply`）：

- 仓库 1.9G → 225M，释放 1769 MB。
- **手写源码 622 个文件，删除前后逐一比对：零丢失、零内容变更。**
- 4 个成品（SaiShot.app / SaiDict.app / SwissKnife.app / SaiPaste.app）全部完好。
- 唯一"消失"的是 `target/release/.fingerprint/` 等 Cargo 指纹缓存，属正常清理。

> 注意：`.json` 不能当源码扩展名来判定。`target/release/.fingerprint/` 下有几百个
> Cargo 生成的 `.json`，把它们算进"源码"会让整块 target 永远删不掉。
> 脚本的 `SOURCE_EXT_NAMES` 已刻意排除 `.json`、`.js`、`.css`、`.html`。

---

## 6. 禁止事项

- 删 `.git`。
- 删任何 `*.app` 或成品文件。
- 往 `build/`、`target/`、`dist/` 里放手写源码后期待它们能被安全清理。
- 用 `rm -rf` 直接清理一个没经过第 0 节判定的目录。
- 在没跑 `--dry-run` 的情况下直接 `--apply` 真实仓库。
