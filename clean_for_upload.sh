#!/bin/bash
# 上传前清理：只删可再生的构建缓存与系统垃圾，保留源码、工程文件、*.app 成品。
#
#   bash clean_for_upload.sh            # 只体检，列出会删什么、能省多少，不动文件
#   bash clean_for_upload.sh --apply    # 真正删除
#
# 安全规则（有其一即跳过）：
#   1. 目录内部包含 *.app 的，整个目录不动（保住编译好的 App）
#   2. .git、*.app 内部、可见的工程文件一律不碰
#   3. 只按固定名单匹配：构建缓存、依赖缓存、Xcode 用户态、Python 缓存、系统垃圾
set -u

ROOT="$(cd "$(dirname "$0")" && pwd)"
APPLY=0
[ "${1:-}" = "--apply" ] && APPLY=1
LOG="$ROOT/.build_clean.log"

# 可以整目录删的构建/依赖缓存
DIR_NAMES=(
  ".build" ".swiftpm" "DerivedData" "xcuserdata"
  "node_modules" "__pycache__" ".pytest_cache" ".venv" "venv" "Pods" ".gradle"
  "dist" ".next" "target"
)
# 可以删的零散垃圾文件
FILE_NAMES=(".DS_Store" "*.pyc" "*.pyo" "*.orig" "*.bak" "~")

freed_kb=0
total_items=0

human() { du -sh "$1" 2>/dev/null | awk '{print $1}'; }
size_kb() { du -sk "$1" 2>/dev/null | awk '{print $1}'; }

echo "目录: $ROOT"
[ "$APPLY" -eq 1 ] && echo "模式: 执行删除" || echo "模式: 仅体检（加 --apply 才会删）"
echo

echo "== 一、构建/依赖缓存目录 =="
while IFS= read -r d; do
  [ -z "$d" ] && continue
  if find "$d" -mindepth 1 -name "*.app" -maxdepth 8 2>/dev/null | grep -q .; then
    echo "  跳过（里面有 .app）: ${d#$ROOT/}"
    continue
  fi
  sz=$(size_kb "$d"); total_items=$((total_items+1)); freed_kb=$((freed_kb+sz))
  echo "  ${d#$ROOT/}  ($(human "$d"))"
  [ "$APPLY" -eq 1 ] && rm -rf -- "$d"
done < <(find "$ROOT" -type d \( \
      -name ".build" -o -name ".swiftpm" -o -name "DerivedData" -o -name "xcuserdata" \
      -o -name "node_modules" -o -name "__pycache__" -o -name ".pytest_cache" \
      -o -name ".venv" -o -name "venv" -o -name "Pods" -o -name ".gradle" \
      -o -name "dist" -o -name ".next" -o -name "target" \) \
    -not -path "*/.git/*" -not -path "*/.app/*" -not -path "*/node_modules/*" 2>/dev/null)

echo
echo "== 二、零散垃圾文件 =="
for p in "${FILE_NAMES[@]}"; do
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    total_items=$((total_items+1))
    sz=$(size_kb "$f"); freed_kb=$((freed_kb+sz))
    echo "  ${f#$ROOT/}"
    [ "$APPLY" -eq 1 ] && rm -rf -- "$f"
  done < <(find "$ROOT" -name "$p" -type f \
      -not -path "*/.git/*" -not -path "*/.app/*" 2>/dev/null)
done

echo
if [ "$total_items" -eq 0 ]; then
  echo "没找到可清理的东西，目录本来就干净。"
else
  echo "共 $total_items 项，约 $((freed_kb/1024)) MB"
  if [ "$APPLY" -eq 1 ]; then
    echo "已删除。目录现在 $(du -sh "$ROOT" | awk '{print $1}')"
  else
    echo "确认无误后执行：bash clean_for_upload.sh --apply"
  fi
fi
echo "$(date '+%F %T') apply=$APPLY items=$total_items kb=$freed_kb" >> "$LOG"
