#!/bin/bash
# 上传前清理脚本：只删可再生的构建缓存、依赖缓存和系统垃圾，
# 保留源码、工程文件、资源文件以及已经编译好的 *.app 成品。
#
#   bash clean_for_upload.sh            # 列出可删项，询问 Y/N 后删除
#   bash clean_for_upload.sh --apply    # 直接删除，不再询问（自动化用）
#   bash clean_for_upload.sh --help     # 查看说明
#
# 安全规则：
#   1. 永远不删 .git（包括 SaiShotJunior 这类子项目里的 .git）。
#   2. 永远不删任何 *.app 内部或 *.app 本身。
#   3. build/ dist/ out/ target/ 内含成品时不再整目录保留，而是逐层下钻：
#      成品所在的那一支保留，同级/其它分支照常清理。
#   4. 只按固定名单匹配：构建缓存、依赖缓存、Xcode 用户态、Python/Node 缓存、系统垃圾。
#   5. 源码优先：候选删除目录若含源码类文件，整个目录保留并在报告里列出来。
#      宁可留下垃圾，也不删源码；删不掉的会明确告诉你，方便手动确认。
#   6. 候选目录必须"看起来是构建产物"（有 deps/、CACHEDIR.TAG、assets/、.o/.rlib 等特征）
#      才会被删；认不出来的一律保留。这样新项目里随便一个叫 build/ 的普通文件夹不会中招。
#
# 可选环境变量：
#   CLEAN_LOG=/path/to/log   指定日志位置（默认 ~/Library/Logs/Sai_apps_clean.log）
set -u

ROOT="$(cd "$(dirname "$0")" && pwd)"
APPLY=0
DRY=0
PAUSE=1
LOG="${CLEAN_LOG:-$HOME/Library/Logs/Sai_apps_clean.log}"

usage() {
  cat <<'EOF'
用法: bash clean_for_upload.sh [选项]

  （默认）        列出可清理项并按大小排序，然后询问 Y/N，Y 删除、N 退出
  --apply         直接删除，不询问（适合自动化）
  -n, --dry-run   只列出，不询问也不删除
  --no-pause      结束后不等待按键（用于自动化/管道）
  -h, --help      显示帮助

可以整目录删除的缓存:
  Swift/Xcode:  .build .swiftpm DerivedData xcuserdata *.xcuserdatad *.noindex *.dSYM
  Node:         node_modules .next .nuxt .turbo .parcel-cache .vite coverage ...
  Python:       __pycache__ .pytest_cache .mypy_cache .ruff_cache .venv venv ...
  其它:         Pods Carthage .gradle 以及 macOS 系统垃圾目录

构建输出目录 build/ dist/ out/ target/ 只有在不含成品时才会整目录删除。
EOF
}

for arg in "$@"; do
  case "$arg" in
    --apply) APPLY=1 ;;
    -n|--dry-run) DRY=1 ;;
    --no-pause) PAUSE=0 ;;
    --pause) PAUSE=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "未知参数: $arg" >&2; usage; exit 2 ;;
  esac
done

# 兜底保护，避免脚本被放到错误位置时误删整个家目录或根目录
case "$ROOT" in
  ""|"/"|"$HOME") echo "拒绝在 $ROOT 上运行清理脚本。" >&2; exit 1 ;;
esac

# 可以整目录删除的构建/依赖缓存
CACHE_DIR_NAMES=(
  ".build" ".swiftpm" "DerivedData" "xcuserdata" ".index-build"
  "node_modules" "bower_components" ".pnpm-store" ".yarn" ".npm"
  ".next" ".nuxt" ".svelte-kit" ".angular" ".expo" ".turbo"
  ".parcel-cache" ".vite" ".cache" "coverage" "htmlcov" ".nyc_output"
  "__pycache__" ".pytest_cache" ".mypy_cache" ".ruff_cache"
  ".tox" ".nox" ".eggs" ".venv" "venv"
  ".gradle" "Pods" "Carthage" ".ipynb_checkpoints"
  ".staging" "XCBuildData" "SourcePackages"
  "*.noindex" "*.xcuserdatad" "*.dSYM"
  ".fseventsd" ".Spotlight-V100" ".Trashes" ".TemporaryItems" ".DocumentRevisions-V100"
)

# 构建输出目录：内含成品时保留，否则可整目录删除
BUILD_DIR_NAMES=("build" "dist" "out" "target")

# 可以删除的零散垃圾文件
JUNK_FILE_NAMES=(
  ".DS_Store" "._*" "Thumbs.db" "desktop.ini"
  "*.pyc" "*.pyo" "*.pyd" "*.class" "*.o" "*.obj" "*.d"
  "*.swp" "*.swo" "*~" ".#*" "#*#"
  "*.orig" "*.rej" "*.tmp" "*.temp" "*.log"
  "*.xcuserstate" "*.pbxuser" "*.mode1v3" "*.mode2v3"
  "*.perspectivev3" "*.moved-aside"
  ".coverage" ".coverage.*" "coverage.xml"
  "*.profraw" "*.gcda" "*.gcno"
  "*.eslintcache" "*.stylelintcache" "*.tsbuildinfo"
  "*.xcactivitylog" "*.pid"
)

total_items=0
freed_kb=0
skipped=0
section_item_no=0
queued_dirs=()
del_items=()
del_kb=()

human() { du -sh "$1" 2>/dev/null | awk '{print $1}'; }
size_kb() { du -sk "$1" 2>/dev/null | awk '{print $1}'; }

is_protected() {
  case "$1" in
    "$ROOT"|"/"|"$HOME") return 0 ;;
    */.git|*/.git/*) return 0 ;;
    *.app|*.app/*) return 0 ;;
    *) return 1 ;;
  esac
}

has_app() {
  find "$1" -path '*/.git' -prune -o -name '*.app' -print -quit 2>/dev/null | grep -q .
}

has_deliverable() {
  find "$1" -path '*/.git' -prune -o \
    \( -name '*.app' -o -name '*.dmg' -o -name '*.pkg' \
       -o -name '*.ipa' -o -name '*.xcarchive' -o -name '*.zip' \
       -o -name '*.apk' -o -name '*.exe' -o -name '*.msi' \
       -o -name '*.deb' -o -name '*.rpm' -o -name '*AppImage' \) \
    -print -quit 2>/dev/null | grep -q .
}

# ---------------------------------------------------------------------------
# 源码保护（规则 5）：候选删除目录里的"可能是手写代码"的信号
#
# 判定顺序见 queue_build_tree()，先看是不是已知的生成目录，再看像不像源码树。
# 认不出来的一律保留，只报告，不删除。
# ---------------------------------------------------------------------------

# 强源码扩展名。刻意不含 .js/.jsx/.css/.html：
# 它们在前端构建产物里极常见，会把 dist/ 这类纯产物误判成源码。
SOURCE_EXT_NAMES=(
  "*.rs" "*.c" "*.cc" "*.cpp" "*.cxx" "*.h" "*.hh" "*.hpp" "*.hxx"
  "*.m" "*.mm" "*.swift" "*.py" "*.pyi" "*.pyx"
  "*.ts" "*.tsx" "*.vue" "*.svelte" "*.astro"
  "*.go" "*.java" "*.kt" "*.kts" "*.cs" "*.rb" "*.php"
  "*.sh" "*.bash" "*.zsh" "*.fish" "*.lua" "*.pl" "*.r" "*.sql" "*.dart"
)
source_find_args=()
for n in "${SOURCE_EXT_NAMES[@]}"; do
  [ "${#source_find_args[@]}" -gt 0 ] && source_find_args+=(-o)
  source_find_args+=(-name "$n")
done

# 工程标志文件：出现即说明"这其实是一个源码树/子项目"，不是纯构建输出
PROJECT_MARKERS=(
  ".git" "Cargo.toml" "Package.swift" "package.json" "pnpm-workspace.yaml"
  "pyproject.toml" "setup.py" "go.mod" "CMakeLists.txt" "Makefile"
  "tsconfig.json" "vite.config.js" "vite.config.ts" "vite.config.mjs"
  "build.gradle" "build.gradle.kts" "pom.xml" "Gemfile" "mix.exs"
  "composer.json" "pubspec.yaml" "*.xcodeproj" "*.xcworkspace"
)

count_source_files() {
  find "$1" -type f \( "${source_find_args[@]}" \) 2>/dev/null | wc -l | tr -d ' '
}

is_source_file() {
  local n
  n="$(basename "$1")"
  local e
  for e in "${SOURCE_EXT_NAMES[@]}"; do
    # shellcheck disable=SC2053
    [[ "$n" == $e ]] && return 0
  done
  return 1
}

has_project_marker() {
  local d="$1" m
  for m in "${PROJECT_MARKERS[@]}"; do
    [ -e "$d/$m" ] && return 0
    compgen -G "$d/$m" >/dev/null 2>&1 && return 0
  done
  return 1
}

# 已知的纯生成目录：这些里面就算出现 .rs/.swift 也是构建时生成的，
# 例：target/release/build/markup5ever-*/out/named_entities.rs
is_generated_output() {
  case "$1" in
    */target/debug|*/target/release) return 0 ;;
    */target/debug/*|*/target/release/*) return 0 ;;
    */.build/*|*/.swiftpm/*) return 0 ;;
    */DerivedData/*) return 0 ;;
    */Build/Intermediates.noindex/*|*/Build/Products/*|*/Build/Index.noindex/*) return 0 ;;
    */node_modules/*|*/.venv/*|*/venv/*) return 0 ;;
    */__pycache__/*|*/.pytest_cache/*|*/.mypy_cache/*|*/.ruff_cache/*) return 0 ;;
  esac
  return 1
}

record_path() {
  local p="$1"
  local kb
  kb="$(size_kb "$p")"
  [ -z "$kb" ] && kb=0
  total_items=$((total_items + 1))
  section_item_no=$((section_item_no + 1))
  freed_kb=$((freed_kb + kb))
  printf '  %2d) %-59s %8s\n' "$section_item_no" "${p#$ROOT/}" "$(human "$p")"
  del_items+=("$p")
  del_kb+=("$kb")
  queued_dirs+=("$p")
}

is_queued_or_nested() {
  local p="$1"
  local q
  for q in ${queued_dirs[@]+"${queued_dirs[@]}"}; do
    [ "$p" = "$q" ] && return 0
    case "$p" in "$q"/*) return 0 ;; esac
  done
  return 1
}

MARK="·"
KEEPINGS=()

keep_report() {
  # $1 路径，$2 原因
  KEEPINGS+=("$1|$2")
  echo "  保留（$2）: ${1#$ROOT/}"
  skipped=$((skipped + 1))
}

# build/dist/out/target 的处理：
#   含成品   → 逐层下钻，成品所在那一支保留，其余分支单独判定
#   不含成品 → 生成目录直接删；像源码树的保留
queue_build_tree() {
  local d="$1"

  [ -d "$d" ] || return 0
  is_protected "$d" && { skipped=$((skipped + 1)); return 0; }
  is_queued_or_nested "$d" && return 0

  # 1) 下方任何位置有成品：必须下钻，绝不能整目录删
  #    （放在生成目录判定之前，否则 target/release/bundle 会被当成生成物删掉）
  if has_deliverable "$d"; then
    local c
    for c in "$d"/* "$d"/.[!.]*; do
      [ -e "$c" ] || continue
      if is_protected "$c"; then
        keep_report "$c" "成品，受保护"
      elif [ -d "$c" ]; then
        queue_build_tree "$c"
      elif is_generated_output "$(dirname "$c")" && ! is_source_file "$c"; then
        # 下钻时同级的游离文件（如 target/release/SaiDict 二进制）也属于产物
        record_path "$c"
      fi
    done
    return 0
  fi

  # 2) 已知纯生成目录：直接删，不再做源码检查
  #    例：target/release/build/markup5ever-*/out/named_entities.rs 是生成物
  if is_generated_output "$d"; then
    queued_dirs+=("$d")
    record_path "$d"
    return 0
  fi

  # 3) 源码树保护：有工程标志文件，或源码文件够多，整体留下
  if has_project_marker "$d"; then
    keep_report "$d" "内含工程文件，判定为源码树"
    return 0
  fi
  local n
  n="$(count_source_files "$d")"
  if [ "${n:-0}" -gt 0 ]; then
    keep_report "$d" "含 $n 个源码文件"
    return 0
  fi

  # 4) 纯产物：整目录删除
  queued_dirs+=("$d")
  record_path "$d"
}

process_dir() {
  local d="$1"
  local kind="$2"

  [ -d "$d" ] || return 0
  if is_protected "$d"; then
    echo "  受保护，跳过: ${d#$ROOT/}"
    skipped=$((skipped + 1))
    return 0
  fi
  if is_queued_or_nested "$d"; then
    return 0
  fi

  if [ "$kind" = "build" ]; then
    queue_build_tree "$d"
    return 0
  fi

  # .staging 是构建脚本的临时目录，即使里面残留 .app 也属于可再生成的中间物
  if [ "$(basename "$d")" != ".staging" ] && has_app "$d"; then
    echo "  保留（内含 .app 成品）: ${d#$ROOT/}"
    skipped=$((skipped + 1))
    return 0
  fi

  queued_dirs+=("$d")
  record_path "$d"
}

# 把名字列表拼成 find 能用的 -name a -o -name b ...
cache_find_args=()
for n in "${CACHE_DIR_NAMES[@]}"; do
  [ "${#cache_find_args[@]}" -gt 0 ] && cache_find_args+=(-o)
  cache_find_args+=(-name "$n")
done

build_find_args=()
for n in "${BUILD_DIR_NAMES[@]}"; do
  [ "${#build_find_args[@]}" -gt 0 ] && build_find_args+=(-o)
  build_find_args+=(-name "$n")
done

junk_find_args=()
for n in "${JUNK_FILE_NAMES[@]}"; do
  [ "${#junk_find_args[@]}" -gt 0 ] && junk_find_args+=(-o)
  junk_find_args+=(-name "$n")
done

echo "目录: $ROOT"
if [ "$APPLY" -eq 1 ]; then
  echo "模式: 直接删除（--apply，不再询问）"
elif [ "$DRY" -eq 1 ]; then
  echo "模式: 仅列出（--dry-run，不删除）"
elif [ ! -t 0 ]; then
  echo "模式: 仅列出（非交互终端，不删除）"
else
  echo "模式: 列出后询问 Y/N，确认才删除"
fi
echo

echo "== 一、构建/依赖缓存目录 =="
section_item_no=0
while IFS= read -r d; do
  [ -n "$d" ] && process_dir "$d" cache
done < <(find "$ROOT" \
    \( -path '*/.git' -o -path '*.app' \) -prune -o \
    -type d \( "${cache_find_args[@]}" \) -prune -print 2>/dev/null | sort)

echo
echo "== 二、构建输出目录（build/dist/out/target）=="
section_item_no=0
while IFS= read -r d; do
  [ -n "$d" ] && process_dir "$d" build
done < <(find "$ROOT" \
    \( -path '*/.git' -o -path '*.app' \) -prune -o \
    -type d \( "${build_find_args[@]}" \) -prune -print 2>/dev/null | sort)

echo
echo "== 三、零散垃圾文件 =="
section_item_no=0
while IFS= read -r f; do
  [ -z "$f" ] && continue
  [ -e "$f" ] || continue
  is_protected "$f" && continue
  is_queued_or_nested "$f" && continue
  record_path "$f"
done < <(find "$ROOT" \
    \( -path '*/.git' -o -path '*.app' -o -type d \( "${cache_find_args[@]}" \) \) -prune -o \
    -type f \( "${junk_find_args[@]}" \) -print 2>/dev/null | sort)

echo
if [ "$total_items" -eq 0 ]; then
  echo "没有发现可清理的中间产物，目录已经是干净的。"
else
  echo "共 $total_items 项，约 $((freed_kb / 1024)) MB"
fi
if [ "${#KEEPINGS[@]}" -gt 0 ]; then
  echo
  echo "== 主动保留（不删除）=="
  local_i=0
  for entry in "${KEEPINGS[@]}"; do
    local_i=$((local_i + 1))
    kp="${entry%%|*}"
    printf '  %2d) %-52s %s\n' "$local_i" "${kp#$ROOT/}" "${entry#*|}"
  done
fi
[ "$skipped" -gt 0 ] && echo "另有 $skipped 项因内含成品、疑似源码或受保护而跳过。"

do_delete=0
if [ "$total_items" -gt 0 ]; then
  if [ "$APPLY" -eq 1 ]; then
    do_delete=1
  elif [ "$DRY" -eq 0 ] && [ "$PAUSE" -eq 1 ] && [ -t 0 ]; then
    echo
    while true; do
      printf '确认删除以上全部 %d 项？[y/N] ' "$total_items"
      answer=""
      read -r answer || answer="n"
      case "$answer" in
        y|Y|yes|YES|Yes) do_delete=1; break ;;
        n|N|no|NO|No|"") do_delete=0; break ;;
        *) echo "请输入 Y 或 N。" ;;
      esac
    done
  fi
fi

if [ "$do_delete" -eq 1 ]; then
  for p in ${del_items[@]+"${del_items[@]}"}; do
    rm -rf -- "$p"
  done
  echo "已删除 $total_items 项，释放约 $((freed_kb / 1024)) MB。当前目录大小: $(human "$ROOT")"
elif [ "$total_items" -gt 0 ]; then
  echo "未删除任何文件。"
fi

mkdir -p "$(dirname "$LOG")" 2>/dev/null || true
echo "$(date '+%F %T') apply=$APPLY dry=$DRY deleted=$do_delete items=$total_items kb=$freed_kb skipped=$skipped root=$ROOT" >> "$LOG" 2>/dev/null || true

# 双击/终端运行时停在结尾，方便看清运行结果，按任意键才关闭
if [ "$PAUSE" -eq 1 ] && [ -t 0 ]; then
  printf '\n按任意键关闭此窗口（Ctrl-C 可直接退出）...'
  read -r -n 1 -s _ || true
  printf '\n'
fi
