#!/bin/bash
set -e

# Build configuration
# - CONFIG=debug|release  (default: debug)
# - UNIVERSAL=1           build a fat arm64+x86_64 binary (default: host arch only)
CONFIG="${CONFIG:-debug}"
UNIVERSAL="${UNIVERSAL:-0}"
INSTALL_AFTER_BUILD="${INSTALL_AFTER_BUILD:-0}"

for arg in "$@"; do
    case "$arg" in
        --universal) UNIVERSAL=1 ;;
        --release)   CONFIG="release" ;;
        --debug)     CONFIG="debug" ;;
        --install)   INSTALL_AFTER_BUILD=1 ;;
    esac
done

# Resolve the SDK explicitly for both configurations. An unqualified SDK lookup
# can retain a stale Command Line Tools path and produce a binary that opts into
# legacy AppKit controls, even when the selected Xcode has a newer SDK.
MACOS_SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
if [ ! -d "$MACOS_SDK_PATH" ] || [ ! -f "$MACOS_SDK_PATH/SDKSettings.plist" ]; then
    echo "error: macOS SDK not found at $MACOS_SDK_PATH" >&2
    exit 1
fi
echo "Using macOS SDK: $MACOS_SDK_PATH"

# Swift's Clang linker invocation can use --sysroot, which does not populate
# Clang's Darwin SDK version. Pass -isysroot as well so LC_BUILD_VERSION records
# the actual SDK instead of the deployment target, preserving modern controls.
SWIFT_SDK_ARGS=(--sdk "$MACOS_SDK_PATH"
    -Xswiftc -Xclang-linker -Xswiftc "-isysroot$MACOS_SDK_PATH")

# Paths
APP_NAME="SaiShotJunior.app"
APP_EXECUTABLE="SaiShotJunior"
APP_DIR="build/$APP_NAME"
# Assemble into a staging bundle first, then sync into $APP_DIR without deleting
# it. Deleting the whole .app makes macOS forget the TCC grants (Screen
# Recording / Accessibility) it gave that app, so a `rm -rf`-style rebuild
# silently loses the permissions.
STAGE_DIR="build/.staging/$APP_NAME"
CONTENTS="$STAGE_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
PLUGINS="$CONTENTS/PlugIns"

# Build binary
if [ "$UNIVERSAL" = "1" ]; then
    echo "Building SaiShot ($CONFIG, universal: arm64 + x86_64)..."
    swift build -c "$CONFIG" "${SWIFT_SDK_ARGS[@]}" --arch arm64 --arch x86_64
    # SwiftPM emits the merged universal binary under .build/apple/Products/<Config>/
    CONFIG_CAP="$(tr '[:lower:]' '[:upper:]' <<< "${CONFIG:0:1}")${CONFIG:1}"
    BUILD_BIN=".build/apple/Products/$CONFIG_CAP/SaiShot"
    if [ ! -f "$BUILD_BIN" ]; then
        # Fallback: merge per-arch binaries with lipo
        ARM_BIN=".build/arm64-apple-macosx/$CONFIG/SaiShot"
        X86_BIN=".build/x86_64-apple-macosx/$CONFIG/SaiShot"
        if [ -f "$ARM_BIN" ] && [ -f "$X86_BIN" ]; then
            BUILD_BIN=".build/$CONFIG/SaiShot-universal"
            lipo -create -output "$BUILD_BIN" "$ARM_BIN" "$X86_BIN"
        else
            echo "error: universal binary not found at $BUILD_BIN and per-arch fallbacks missing" >&2
            exit 1
        fi
    fi
else
    echo "Building SaiShot ($CONFIG, host arch only)..."
    swift build -c "$CONFIG" "${SWIFT_SDK_ARGS[@]}"
    BUILD_BIN=".build/$CONFIG/SaiShot"
fi

if [ ! -f "$BUILD_BIN" ]; then
    echo "error: app binary not found at $BUILD_BIN" >&2
    exit 1
fi

# Clean previous staging bundle (the published $APP_DIR is synced in place below)
rm -rf build/.staging

# Create .app bundle structure
mkdir -p "$MACOS"
mkdir -p "$RESOURCES"
# Copy binary
cp "$BUILD_BIN" "$MACOS/$APP_EXECUTABLE"

# Copy Info.plist
cp "SaiShot/App/Info.plist" "$CONTENTS/Info.plist"
bash scripts/inject-build-metadata.sh "$CONTENTS/Info.plist"
APP_SHORT_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$CONTENTS/Info.plist")"
APP_BUNDLE_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$CONTENTS/Info.plist")"

# Copy app icon
cp "Resources/AppIcon.icns" "$RESOURCES/AppIcon.icns"

# Copy menu bar icon source. The SVG lives in design/ so tweaking it updates the
# app bundle on the next rebuild without touching Swift code.
cp "design/menuBarIcon.svg" "$RESOURCES/MenuBarIcon.svg"

# Copy localization bundles (.lproj). The app loads these directly for its
# in-app language picker — see Localizer.swift.
for lproj in Resources/*.lproj; do
    [ -d "$lproj" ] || continue
    cp -R "$lproj" "$RESOURCES/"
done

# Copy SwiftPM resource bundles. PermissionFlow uses Bundle.module for its
# floating authorization panel strings; if this bundle is absent, Intel builds
# crash with a Swift assertion the first time the panel is shown.
BUILD_DIR="$(dirname "$BUILD_BIN")"
PERMISSION_FLOW_BUNDLE="$BUILD_DIR/SaiShot_PermissionFlow.bundle"
if [ ! -d "$PERMISSION_FLOW_BUNDLE" ]; then
    echo "error: missing SwiftPM resource bundle: $PERMISSION_FLOW_BUNDLE" >&2
    exit 1
fi
cp -R "$PERMISSION_FLOW_BUNDLE" "$RESOURCES/"

# Publish: sync staging contents into $APP_DIR, keeping the bundle root (and its
# TCC grants) alive. --delete clears files removed from the bundle.
mkdir -p "$APP_DIR"
rsync -a --delete "$STAGE_DIR/" "$APP_DIR/"
rm -rf build/.staging

# Code signing
# -----------------------------------------------------------------------------
# Sign with the SAME self-signed certificate CI uses ("SaiShot Self-Signed") so
# the app's code-signing identity — and therefore its macOS TCC permission
# grants (Screen Recording / Accessibility) — stay stable between local test
# builds and released builds. Without this, every local rebuild looks like a
# different app to TCC and you must re-authorize.
#
# Import the cert once (it lives in SaiShot-signing.p12, default password "SaiShot"):
#   security import ~/Desktop/SaiShot-signing.p12 \
#     -k ~/Library/Keychains/login.keychain-db -P SaiShot -T /usr/bin/codesign
#
# Override the identity with the SIGN_IDENTITY env var. If the cert isn't in the
# keychain, fall back to ad-hoc signing (still launchable, but TCC grants won't
# match released builds).
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SIGN_IDENTITY="${SIGN_IDENTITY:-SaiShot Self-Signed}"
# Dedicated keychain holding the identity, so signing never opens a password
# sheet. Its password is not secret (local dev only) and is only used to unlock
# it after a reboot; the partition list below lets codesign use the key
# silently.
SIGN_KEYCHAIN="${SIGN_KEYCHAIN:-$HOME/Library/Keychains/saishot-signing.keychain-db}"
SIGN_KEYCHAIN_PASS="${SIGN_KEYCHAIN_PASS:-SaiShot}"
sign_bundles() {
    local identity="$1"
    local use_dedicated_keychain="$2"
    local keychain_args=()
    if [ "$use_dedicated_keychain" = "1" ] && [ -f "$SIGN_KEYCHAIN" ] && [ "$identity" != "-" ]; then
        security unlock-keychain -p "$SIGN_KEYCHAIN_PASS" "$SIGN_KEYCHAIN" >/dev/null 2>&1 || true
        security set-key-partition-list -S apple-tool:,apple:,codesign: \
            -s -k "$SIGN_KEYCHAIN_PASS" "$SIGN_KEYCHAIN" >/dev/null 2>&1 || true
        keychain_args=(--keychain "$SIGN_KEYCHAIN")
    fi
    codesign --force "${keychain_args[@]}" --entitlements "$SCRIPT_DIR/SaiShot.entitlements" \
        --sign "$identity" "$APP_DIR"
}

identity_is_available() {
    local keychain="$1"
    if [ -n "$keychain" ]; then
        security find-identity -p codesigning "$keychain" 2>/dev/null | grep -qF "$SIGN_IDENTITY"
    else
        security find-identity -p codesigning 2>/dev/null | grep -qF "$SIGN_IDENTITY"
    fi
}

if identity_is_available "$SIGN_KEYCHAIN"; then
    echo "Signing with: $SIGN_IDENTITY"
    if ! sign_bundles "$SIGN_IDENTITY" 1; then
        echo "error: signing with '$SIGN_IDENTITY' failed" >&2
        exit 1
    fi
elif identity_is_available ""; then
    # The certificate is commonly imported into the login keychain, so fall back
    # to the default search list before giving up on a stable signing identity.
    echo "Signing with: $SIGN_IDENTITY (default keychain)"
    if ! sign_bundles "$SIGN_IDENTITY" 0; then
        echo "error: signing with '$SIGN_IDENTITY' failed" >&2
        exit 1
    fi
else
    echo "warning: '$SIGN_IDENTITY' not found in any keychain — falling back to ad-hoc signing." >&2
    echo "warning: TCC permissions won't match released builds until you import SaiShot-signing.p12." >&2
    sign_bundles - 0
fi

echo "✅ Built and signed $APP_DIR"

# Optional install. Copy *into* the existing app directory instead of deleting
# and recreating it: macOS drops an app's TCC grants (screen recording,
# accessibility) when the app bundle it remembers disappears, which is why
# every `rm -rf`-style rebuild used to lose the permissions. Keeping the bundle
# root in place and only syncing its contents keeps the grants.
install_app() {
    local dest_dir="${INSTALL_DIR:-$HOME/Applications}"
    local dest="$dest_dir/$(basename "$APP_DIR")"
    mkdir -p "$dest"
    rsync -a --delete "$APP_DIR/" "$dest/"
    echo "✅ Installed to $dest"
}

if [ "$INSTALL_AFTER_BUILD" = "1" ]; then
    install_app
    echo "   (launch it once with: open \"${INSTALL_DIR:-$HOME/Applications}/$(basename "$APP_DIR")\")"
fi
ARCHS=$(lipo -archs "$APP_DIR/Contents/MacOS/$APP_EXECUTABLE" 2>/dev/null || echo "unknown")
echo "   Architectures: $ARCHS"
echo ""
echo "To run:"
echo "  open build/$APP_NAME"
echo ""
echo "Optional install (keeps the install bundle in place):"
echo "  bash scripts/bundle.sh --install"
