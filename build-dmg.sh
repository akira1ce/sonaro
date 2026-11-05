#!/usr/bin/env bash
#
# Build Sonaro (macOS, Release) and package it into a distributable DMG.
#
#   ./build-dmg.sh
#
# Output: dist/Sonaro-<version>.dmg, version read from the built app's Info.plist.
# The window/icon layout is applied by create-dmg, which briefly mounts a
# temporary read-write image and drives Finder, so a Finder window appears.
# Requires: Xcode and create-dmg (brew install create-dmg).

set -euo pipefail

APP_NAME="Sonaro"
SCHEME="Sonaro"
CONFIGURATION="Release"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$ROOT/build"
DIST_DIR="$ROOT/dist"
APP_PATH="$BUILD_DIR/Build/Products/$CONFIGURATION/$APP_NAME.app"

cd "$ROOT"

if ! command -v create-dmg >/dev/null 2>&1; then
    echo "❌ 缺少 create-dmg，请先安装：brew install create-dmg" >&2
    exit 1
fi

# create-dmg writes to dist/rw.<pid>.Sonaro-<version>.dmg; clean it up if the
# run is interrupted so no temporary image is left behind.
cleanup() { rm -f "$DIST_DIR"/rw.*."${APP_NAME}"*.dmg "$ROOT"/rw.*."${APP_NAME}"*.dmg; }
trap cleanup EXIT

echo "🧹 清理旧的构建产物..."
rm -rf "$APP_PATH"

echo "🔨 正在构建应用..."
xcodebuild -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -derivedDataPath "$BUILD_DIR" \
    -destination 'generic/platform=macOS' \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO \
    build

if [ ! -d "$APP_PATH" ]; then
    echo "❌ 错误：找不到构建的应用（$APP_PATH）" >&2
    exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")"
DMG="$DIST_DIR/${APP_NAME}-${VERSION}.dmg"

echo "✅ 应用构建完成: $APP_PATH ($VERSION)"

echo "📦 正在创建 DMG..."
mkdir -p "$DIST_DIR"
rm -f "$DMG"
create-dmg \
    --volname "$APP_NAME" \
    --volicon "$APP_PATH/Contents/Resources/AppIcon.icns" \
    --window-pos 200 120 \
    --window-size 660 450 \
    --icon-size 128 \
    --icon "$APP_NAME.app" 180 200 \
    --hide-extension "$APP_NAME.app" \
    --app-drop-link 480 200 \
    --no-internet-enable \
    "$DMG" \
    "$APP_PATH"

echo "✅ DMG 创建完成: $DMG"
echo "📊 DMG 大小: $(du -h "$DMG" | cut -f1)"
echo ""
echo "⚠️  应用未签名，仅供个人使用；首次打开需右键 → 打开"
