#!/usr/bin/env bash
# Build BiliCast.app — one-shot script that:
#   1. Builds the Go backend daemon (bilicastd)
#   2. Builds the Swift macOS app
#   3. Assembles the .app bundle with bilicastd + ffmpeg
#   4. Ad-hoc signs and clears quarantine
#   5. Packs into BiliCast.app.zip
#
# Usage:
#   ./build.sh                        # darwin-arm64, debug-ish (swift build -c release)
#   ./build.sh --arch amd64           # darwin-amd64
#   ./build.sh --skip-go              # skip Go rebuild (use existing binary)
#   ./build.sh --zip-only             # only re-pack existing .app
#
# Env vars:
#   APP_VERSION   — version string (default: auto-detected from git tag)
#   BILICAST_SKIP_FFMPEG=1 — skip ffmpeg download entirely

set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
CROSSPLATFORM="$ROOT/../crossplatform"
APP_NAME="BiliCast"
BUILD_DIR="$ROOT/build"
APP_PATH="$BUILD_DIR/$APP_NAME.app"
CONTENTS="$APP_PATH/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RESOURCES_DIR="$CONTENTS/Resources"

ARCH="${ARCH:-arm64}"
SKIP_GO=false
ZIP_ONLY=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --arch) ARCH="$2"; shift 2 ;;
    --skip-go) SKIP_GO=true; shift ;;
    --zip-only) ZIP_ONLY=true; shift ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

# --- version detection ---
if [[ -z "${APP_VERSION:-}" ]]; then
  APP_VERSION="$(git -C "$ROOT" describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || echo "0.4.0")"
fi
echo "==> BiliCast v$APP_VERSION  arch=$ARCH"

# ============================================================================
# Step 1 — Build Go backend (bilicastd)
# ============================================================================
if $ZIP_ONLY; then
  echo "==> [skip] zip-only mode, skipping builds"
elif $SKIP_GO; then
  echo "==> [skip] Go backend (--skip-go)"
else
  echo "==> Building Go backend (darwin-$ARCH)..."

  GO_BINARY="$CROSSPLATFORM/dist/bilicastd-darwin-$ARCH"
  cd "$CROSSPLATFORM"
  if [[ "$ARCH" == "arm64" ]]; then
    GOOS=darwin GOARCH=arm64 go build -o "$GO_BINARY" ./cmd/bilicastd/
  else
    GOOS=darwin GOARCH=amd64 go build -o "$GO_BINARY" ./cmd/bilicastd/
  fi
  cd "$ROOT"

  echo "  ok: $(file -b "$GO_BINARY" | head -c 60)"
  ls -lh "$GO_BINARY"
fi

# ============================================================================
# Step 2 — Build Swift app
# ============================================================================
if ! $ZIP_ONLY; then
  echo "==> Building Swift app..."
  cd "$ROOT"
  swift build --configuration release 2>&1 | tail -3

  SWIFT_BINARY="$ROOT/.build/arm64-apple-macosx/release/$APP_NAME"
  if [[ ! -f "$SWIFT_BINARY" ]]; then
    echo "ERROR: Swift build did not produce $SWIFT_BINARY" >&2
    exit 1
  fi
  echo "  ok: $(file -b "$SWIFT_BINARY" | head -c 60)"
fi

# ============================================================================
# Step 3 — Assemble .app bundle
# ============================================================================
echo "==> Assembling $APP_NAME.app..."

rm -rf "$APP_PATH"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

# --- Swift binary ---
cp "$ROOT/.build/arm64-apple-macosx/release/$APP_NAME" "$MACOS_DIR/$APP_NAME"
chmod +x "$MACOS_DIR/$APP_NAME"

# --- Go daemon ---
GO_BINARY="$CROSSPLATFORM/dist/bilicastd-darwin-$ARCH"
if [[ -f "$GO_BINARY" ]]; then
  cp "$GO_BINARY" "$MACOS_DIR/bilicastd"
  chmod +x "$MACOS_DIR/bilicastd"
  echo "  bundled bilicastd ($ARCH)"
else
  echo "  WARNING: bilicastd not found at $GO_BINARY — app will fail at runtime" >&2
fi

# --- ffmpeg ---
FFMPEG_LIB="$ROOT/lib/ffmpeg"
if [[ "${BILICAST_SKIP_FFMPEG:-0}" == "1" ]]; then
  echo "  [skip] ffmpeg (BILICAST_SKIP_FFMPEG=1)"
elif [[ -f "$FFMPEG_LIB" ]]; then
  cp "$FFMPEG_LIB" "$RESOURCES_DIR/ffmpeg"
  echo "  ffmpeg (from lib/)"
else
  echo "  fetching ffmpeg..."
  "$ROOT/tools/fetch-ffmpeg.sh" "$FFMPEG_LIB" && {
    cp "$FFMPEG_LIB" "$RESOURCES_DIR/ffmpeg"
    echo "  ffmpeg (downloaded → lib/)"
  } || {
    echo "  WARNING: ffmpeg download failed — app will rely on system ffmpeg" >&2
  }
fi

# --- App icon ---
# Always use the high-quality icon from Resources/ (3.1 MB, 16-bit P3)
# NOT the DMG volume icon — that's lower quality and only for the DMG background
if [[ -f "$ROOT/Resources/AppIcon.icns" ]]; then
  cp "$ROOT/Resources/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
else
  echo "  WARNING: AppIcon.icns not found — app will have default icon" >&2
fi

# --- Info.plist ---
cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>com.jianzhou.bilicast</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundleVersion</key>
  <string>$APP_VERSION</string>
  <key>CFBundleShortVersionString</key>
  <string>$APP_VERSION</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

# ============================================================================
# Step 4 — Sign & clear quarantine
# ============================================================================
echo "==> Signing (ad-hoc)..."
codesign --force --deep --sign - "$APP_PATH" 2>&1

echo "==> Clearing quarantine..."
xattr -dr com.apple.quarantine "$APP_PATH" 2>/dev/null || true

# ============================================================================
# Step 5 — Pack zip
# ============================================================================
ZIP_PATH="$BUILD_DIR/$APP_NAME.app.zip"
rm -f "$ZIP_PATH"
echo "==> Packing $ZIP_PATH..."
cd "$BUILD_DIR"
zip -r "$APP_NAME.app.zip" "$APP_NAME.app" 2>&1 | tail -1
ls -lh "$ZIP_PATH"

echo ""
echo "==> Done: $ZIP_PATH"
echo "    $APP_NAME v$APP_VERSION ($ARCH)"
