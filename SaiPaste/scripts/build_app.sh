#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-1.0.0}"
BUILD="${BUILD:-1}"
APP="packaging/SaiPaste.app"

echo "==> Building universal release binary (arm64 + x86_64)"
swift build -c release --arch arm64 --arch x86_64

BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/SaiPaste"
echo "    binary: $BIN"

echo "==> Generating icon"
bash scripts/make_icon.sh >/dev/null

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/SaiPaste"
cp packaging/SaiPaste.icns "$APP/Contents/Resources/SaiPaste.icns"
# SwiftPM resources (the menu-bar template icon) travel as their own bundle.
RESOURCE_BUNDLE="$(dirname "$BIN")/SaiPaste_SaiPaste.bundle"
[ -d "$RESOURCE_BUNDLE" ] && cp -R "$RESOURCE_BUNDLE" "$APP/Contents/Resources/"

sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" \
    packaging/Info.plist > "$APP/Contents/Info.plist"

printf 'APPL????' > "$APP/Contents/PkgInfo"

# Explicitly sign the assembled bundle with a stable designated requirement.
# Without this, each release build only carries Swift's per-binary linker
# signature (a changing CDHash), which makes macOS ask for Accessibility again.
echo "==> Signing $APP"
/usr/bin/codesign --force --sign - --identifier com.greycorelabs.saipaste \
  -r='designated => identifier "com.greycorelabs.saipaste"' "$APP"

echo "==> Built $APP"
/usr/bin/file "$APP/Contents/MacOS/SaiPaste"
echo "    version $VERSION ($BUILD)"
