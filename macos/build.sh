#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="BiliCast"
EXEC_NAME="BiliCast"
DISPLAY_NAME="BiliCast"
BUNDLE_ID="local.bilicast"
APP_VERSION="${APP_VERSION:-0.4.0}"
APP_BUILD="${APP_BUILD:-$APP_VERSION}"
APP_BUILD_TIME="${APP_BUILD_TIME:-$(date '+%Y-%m-%d %H:%M:%S %z')}"
DEPLOYMENT_TARGET="${DEPLOYMENT_TARGET:-13.0}"

# Set BILICAST_SKIP_FFMPEG=1 to skip downloading ffmpeg (the .app will fall back
# to the user's system ffmpeg at runtime — dashRemux degrades if no system ffmpeg).
SKIP_FFMPEG="${BILICAST_SKIP_FFMPEG:-0}"

APP="$ROOT/build/$APP_NAME.app"
RESOURCES="$APP/Contents/Resources"
SOURCE_RESOURCES="$ROOT/Resources"
APP_ICON="$SOURCE_RESOURCES/AppIcon.icns"
BUNDLED_FFMPEG_CACHE="$SOURCE_RESOURCES/ffmpeg"

rm -rf "$ROOT/build"
mkdir -p "$APP/Contents/MacOS" "$RESOURCES"

# Step 1: ensure we have a bundle-able ffmpeg (cached at Resources/ffmpeg).
if [[ "$SKIP_FFMPEG" != "1" ]]; then
  if [[ ! -x "$BUNDLED_FFMPEG_CACHE" ]]; then
    echo "==> bundled ffmpeg not cached at $BUNDLED_FFMPEG_CACHE; fetching..."
    mkdir -p "$SOURCE_RESOURCES"
    if "$ROOT/tools/fetch-ffmpeg.sh" "$BUNDLED_FFMPEG_CACHE"; then
      echo "==> fetched and cached"
    else
      echo "  ! ffmpeg fetch failed; .app will rely on system ffmpeg at runtime"
      rm -f "$BUNDLED_FFMPEG_CACHE"
    fi
  else
    echo "==> using cached ffmpeg at $BUNDLED_FFMPEG_CACHE"
  fi
fi

# App icon — generate if missing or REGENERATE_APP_ICON=1.
if [[ "${REGENERATE_APP_ICON:-0}" == "1" || ! -f "$APP_ICON" ]]; then
  mkdir -p "$SOURCE_RESOURCES"
  ICONSET="$ROOT/build/AppIcon.iconset"
  echo "==> generating app icon (emoji 🐝)"
  swift "$ROOT/tools/make_app_icon.swift" "$ICONSET" "🐝"
  iconutil -c icns "$ICONSET" -o "$APP_ICON"
  rm -rf "$ICONSET"
fi

echo "==> swift build (universal release)"
swift build -c release --arch arm64 --arch x86_64 --product "$EXEC_NAME"

BUILT_BIN="$ROOT/.build/apple/Products/Release/$EXEC_NAME"
if [[ ! -f "$BUILT_BIN" ]]; then
  echo "build artifact missing: $BUILT_BIN" >&2
  exit 1
fi

cp "$BUILT_BIN" "$APP/Contents/MacOS/$EXEC_NAME"
chmod +x "$APP/Contents/MacOS/$EXEC_NAME"

# Bundle resources
if [[ -f "$APP_ICON" ]]; then
  cp "$APP_ICON" "$RESOURCES/AppIcon.icns"
  ICON_KEY_BLOCK="  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIconName</key>
  <string>AppIcon</string>"
else
  ICON_KEY_BLOCK=""
fi

if [[ -x "$BUNDLED_FFMPEG_CACHE" ]]; then
  cp "$BUNDLED_FFMPEG_CACHE" "$RESOURCES/ffmpeg"
  chmod +x "$RESOURCES/ffmpeg"
  echo "==> bundled ffmpeg into .app/Contents/Resources/ffmpeg"
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>$EXEC_NAME</string>
$ICON_KEY_BLOCK
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$DISPLAY_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$DISPLAY_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$APP_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$APP_BUILD</string>
  <key>BuildTime</key>
  <string>$APP_BUILD_TIME</string>
  <key>LSMinimumSystemVersion</key>
  <string>$DEPLOYMENT_TARGET</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true

echo "==> built $APP"
