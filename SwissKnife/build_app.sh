#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$ROOT_DIR/SwissKnife.app"
EXECUTABLE_PATH="$ROOT_DIR/.build/release/SwissKnife"

cd "$ROOT_DIR"
swift build -c release

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp "$ROOT_DIR/Support/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$ROOT_DIR/Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
cp "$ROOT_DIR/Resources/Sounds/"*.wav "$APP_DIR/Contents/Resources/"
cp "$EXECUTABLE_PATH" "$APP_DIR/Contents/MacOS/SwissKnife"
chmod +x "$APP_DIR/Contents/MacOS/SwissKnife"

codesign --force --sign - "$APP_DIR"

echo ""
echo "✅ 构建完成：$APP_DIR"
