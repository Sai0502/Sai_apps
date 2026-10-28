#!/bin/bash
# Sai_apps 编译缓存清理脚本
# 只删除各项目 .build/ 编译中间产物（SwiftPM 缓存），保留 build/ 输出目录、.app 成品与源码。
# 用法: bash clean_builds.sh    （可被定时任务调用）
set -u

ROOT="$(cd "$(dirname "$0")" && pwd)"
LOG="$ROOT/.build_clean.log"
echo "== $(date '+%Y-%m-%d %H:%M:%S') 清理开始 =="

before=$(du -sk "$ROOT" 2>/dev/null | awk '{print $1}')
freed=0

while IFS= read -r d; do
    # 安全校验：若 .build 内存在 .app 成品，跳过不删
    if find "$d" -name "*.app" -maxdepth 6 2>/dev/null | grep -q .; then
        echo "  跳过（内含 .app）: $d"
        continue
    fi
    sz=$(du -sk "$d" 2>/dev/null | awk '{print $1}')
    rm -rf -- "$d"
    freed=$((freed + sz))
    echo "  已删除: $d (${sz} KB)"
done < <(find "$ROOT" -type d -name ".build" \
    -not -path "*/node_modules/*" -not -path "*/.git/*" 2>/dev/null)

after=$(du -sk "$ROOT" 2>/dev/null | awk '{print $1}')
echo "  清理前 ${before} KB → 清理后 ${after} KB，释放 ${freed} KB"
echo "== $(date '+%Y-%m-%d %H:%M:%S') 清理结束，释放 ${freed} KB ==" >> "$LOG"
