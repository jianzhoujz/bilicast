#!/usr/bin/env bash
#
# Downloads a static ffmpeg binary, lipos arm64+x86_64 into a universal binary,
# writes to $1.
#
# We try multiple mirrors and fall back gracefully. If everything fails, we exit
# non-zero so build.sh can warn the user and continue (the .app still builds, it
# just relies on the user's system ffmpeg at runtime).
#
# Override mirrors with env vars:
#   FFMPEG_ARM64_URL=...
#   FFMPEG_X86_64_URL=...
#
# To bypass entirely, set BILICAST_SKIP_FFMPEG=1 in the calling environment.

set -euo pipefail

DEST="${1:-}"
if [[ -z "$DEST" ]]; then
  echo "usage: $0 <output-path>" >&2
  exit 2
fi

WORK="$(mktemp -d)"
trap "rm -rf '$WORK'" EXIT

# --- helpers --------------------------------------------------------------

# extract_ffmpeg <archive-path> <work-subdir>
# After extraction, prints the path to the ffmpeg binary on stdout.
extract_ffmpeg() {
  local archive="$1" subdir="$2"
  local out="$WORK/$subdir"
  mkdir -p "$out"
  case "$archive" in
    *.zip)
      unzip -q -o "$archive" -d "$out" ;;
    *.gz|*.tar.gz)
      if [[ "$archive" == *.tar.gz ]]; then
        tar -xzf "$archive" -C "$out"
      else
        gunzip -c "$archive" > "$out/ffmpeg"
      fi ;;
    *.7z)
      7z x -y -o"$out" "$archive" >/dev/null ;;
    *)
      cp "$archive" "$out/ffmpeg" ;;
  esac
  find "$out" -type f -name "ffmpeg" -perm +111 -print -quit 2>/dev/null \
    || find "$out" -type f -name "ffmpeg" -print -quit
}

try_download() {
  local url="$1" out="$2"
  # Long max-time since proxies and CDN can be slow; retry with delay on transient failures.
  curl -fL --silent --show-error \
    --connect-timeout 30 --max-time 600 \
    --retry 3 --retry-delay 2 --retry-connrefused \
    -o "$out" "$url"
}

# fetch_arch <arch> <output-binary-path>
# Tries a list of mirrors for the given arch. Returns 0 if any worked.
fetch_arch() {
  local arch="$1" target="$2"
  local urls=()
  if [[ "$arch" == "arm64" ]]; then
    urls+=("${FFMPEG_ARM64_URL:-}")
    urls+=("https://www.osxexperts.net/ffmpeg711arm.zip")
  else
    urls+=("${FFMPEG_X86_64_URL:-}")
    # The "getrelease" path issues a 302 to a versioned mirror; specific URL more reliable in slow networks.
    urls+=("https://evermeet.cx/pub/ffmpeg/ffmpeg-8.1.zip")
    urls+=("https://evermeet.cx/ffmpeg/getrelease/zip")
  fi
  local tries=0
  for url in "${urls[@]}"; do
    [[ -z "$url" ]] && continue
    tries=$((tries + 1))
    local ext="${url##*.}"
    local archive="$WORK/${arch}-${tries}.${ext}"
    echo "  [$arch] try $url"
    if try_download "$url" "$archive"; then
      local bin
      bin="$(extract_ffmpeg "$archive" "${arch}-${tries}-extracted" || true)"
      if [[ -n "$bin" && -f "$bin" ]]; then
        chmod +x "$bin"
        cp "$bin" "$target"
        return 0
      fi
      echo "    ! could not locate ffmpeg in archive"
    else
      echo "    ! download failed"
    fi
  done
  return 1
}

# --- main -----------------------------------------------------------------

ARM_BIN="$WORK/ffmpeg-arm64"
X86_BIN="$WORK/ffmpeg-x86_64"

echo "==> fetching arm64 ffmpeg..."
if ! fetch_arch arm64 "$ARM_BIN"; then
  echo "  ! all arm64 mirrors failed" >&2
  exit 1
fi
echo "  ok: $(file -b "$ARM_BIN" | head -c 80)"

echo "==> fetching x86_64 ffmpeg..."
if ! fetch_arch x86_64 "$X86_BIN"; then
  echo "  ! all x86_64 mirrors failed" >&2
  exit 1
fi
echo "  ok: $(file -b "$X86_BIN" | head -c 80)"

mkdir -p "$(dirname "$DEST")"
echo "==> creating universal binary at $DEST"
lipo -create "$ARM_BIN" "$X86_BIN" -output "$DEST"
chmod +x "$DEST"

echo "==> done"
file "$DEST"
ls -lh "$DEST"
