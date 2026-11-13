#!/usr/bin/env bash
#
# Build Sonaro (macOS, Release) and package it into a DMG.
#
#   ./build-dmg.sh
#
# Output: dist/Sonaro-<version>.dmg, version read from the built app's Info.plist.
# The image is created by hdiutil from a staging folder holding the app and an
# /Applications alias, so no Finder automation or third-party tool is needed.
# Requires: Xcode with the Apple Development identity for DEVELOPMENT_TEAM
# (so the Keychain items survive reinstalls).

set -euo pipefail

APP_NAME="Sonaro"
SCHEME="Sonaro"
CONFIGURATION="Release"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$ROOT/build"
DIST_DIR="$ROOT/dist"
APP_PATH="$BUILD_DIR/Build/Products/$CONFIGURATION/$APP_NAME.app"
STAGE_DIR="$BUILD_DIR/dmg-stage"
LOG="$BUILD_DIR/package.log"

cd "$ROOT"
rm -rf "$APP_PATH" "$STAGE_DIR"
mkdir -p "$BUILD_DIR" "$STAGE_DIR" "$DIST_DIR"

echo "🔨 构建 ${APP_NAME}…"
if ! xcodebuild -scheme "$SCHEME" \
        -configuration "$CONFIGURATION" \
        -derivedDataPath "$BUILD_DIR" \
        -destination 'generic/platform=macOS' \
        build >"$LOG" 2>&1; then
    echo "❌ 构建失败:" >&2
    grep -m 20 "error:" "$LOG" >&2 || tail -30 "$LOG" >&2
    echo "完整日志: $LOG" >&2
    exit 1
fi

if [ ! -d "$APP_PATH" ]; then
    echo "❌ 找不到构建产物: $APP_PATH" >&2
    exit 1
fi

# An ad-hoc signature changes its identity on every build, which invalidates the
# Keychain ACLs and makes macOS ask for the login password after each reinstall.
TEAM="$(codesign -dv "$APP_PATH" 2>&1 | sed -n 's/^TeamIdentifier=//p')"
if [ -z "$TEAM" ] || [ "$TEAM" = "not set" ]; then
    echo "❌ 应用没有开发者签名（TeamIdentifier=${TEAM:-无}），重装会再次要求钥匙串密码" >&2
    exit 1
fi
codesign --verify --strict "$APP_PATH"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")"
DMG="$DIST_DIR/${APP_NAME}-${VERSION}.dmg"

echo "📦 打包 DMG…"
ditto "$APP_PATH" "$STAGE_DIR/$APP_NAME.app"
ln -s /Applications "$STAGE_DIR/Applications"
rm -f "$DMG"
if ! hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE_DIR" -ov -format UDZO "$DMG" >"$LOG" 2>&1; then
    echo "❌ DMG 创建失败:" >&2
    cat "$LOG" >&2
    exit 1
fi

rm -rf "$STAGE_DIR" "$LOG"

echo "✅ dist/${APP_NAME}-${VERSION}.dmg ($(du -h "$DMG" | cut -f1))"
