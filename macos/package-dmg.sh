#!/usr/bin/env bash
# Build BiliCastHelper.app and pack it into dist/BiliCastHelper-VERSION.dmg.
#
# Layout: a clean DMG with the .app + a /Applications symlink. No fancy Finder
# background — the user just drags the app onto Applications.
#
# Usage:
#   ./package-dmg.sh                # uses default version from build.sh
#   APP_VERSION=0.4.0 ./package-dmg.sh

set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="BiliCastHelper"
APP_VERSION="${APP_VERSION:-${VERSION:-0.3.0}}"
APP_BUILD="${APP_BUILD:-$APP_VERSION}"

APP_PATH="$ROOT/build/$APP_NAME.app"
DIST_DIR="$ROOT/dist"
WORK_DIR="$ROOT/build/dmg-$APP_NAME"
STAGE_DIR="$WORK_DIR/stage"
RW_DMG="$WORK_DIR/$APP_NAME-rw.dmg"
FINAL_DMG="$DIST_DIR/$APP_NAME-$APP_VERSION.dmg"
VOLUME_NAME="$APP_NAME"
MOUNT_DIR="/Volumes/$VOLUME_NAME"

# Always rebuild the .app so we ship a fresh universal binary + bundled ffmpeg.
APP_VERSION="$APP_VERSION" APP_BUILD="$APP_BUILD" "$ROOT/build.sh" >/dev/null

rm -rf "$WORK_DIR"
mkdir -p "$STAGE_DIR" "$DIST_DIR"

cp -R "$APP_PATH" "$STAGE_DIR/"
ln -s /Applications "$STAGE_DIR/Applications"

hdiutil create \
  -volname "$VOLUME_NAME" \
  -fs HFS+ \
  -srcfolder "$STAGE_DIR" \
  -ov \
  -format UDRW \
  "$RW_DMG" >/dev/null

cleanup() {
  hdiutil detach "$MOUNT_DIR" >/dev/null 2>&1 || true
  rmdir "$MOUNT_DIR" >/dev/null 2>&1 || true
}
trap cleanup EXIT

hdiutil detach "$MOUNT_DIR" >/dev/null 2>&1 || true
rmdir "$MOUNT_DIR" >/dev/null 2>&1 || true

hdiutil attach "$RW_DMG" \
  -readwrite \
  -noverify \
  -noautoopen \
  -mountpoint "$MOUNT_DIR" >/dev/null

# Minimal Finder layout — icons in icon view with a sensible window size.
osascript <<APPLESCRIPT
tell application "Finder"
  tell disk "$VOLUME_NAME"
    open
    delay 1
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set bounds of container window to {200, 200, 700, 500}
    set theViewOptions to icon view options of container window
    set arrangement of theViewOptions to not arranged
    set icon size of theViewOptions to 96
    set text size of theViewOptions to 12
    set position of item "$APP_NAME.app" of container window to {130, 140}
    set position of item "Applications" of container window to {380, 140}
    update without registering applications
    delay 1
    close
  end tell
end tell
APPLESCRIPT

sync
hdiutil detach "$MOUNT_DIR" >/dev/null
trap - EXIT

rm -f "$FINAL_DMG"
hdiutil convert "$RW_DMG" \
  -format UDZO \
  -imagekey zlib-level=9 \
  -o "$FINAL_DMG" >/dev/null

rm -rf "$WORK_DIR"

echo "$FINAL_DMG"
ls -lh "$FINAL_DMG"
shasum -a 256 "$FINAL_DMG"
