# BiliCast

![macOS](https://img.shields.io/badge/macOS-13.0%2B-black)
![Apple Silicon](https://img.shields.io/badge/Apple%20Silicon-supported-brightgreen)
![Intel](https://img.shields.io/badge/Intel-supported-brightgreen)
![Release](https://img.shields.io/github/v/release/jianzhoujz/bilicast)

Cast Bilibili web videos to a DLNA TV / projector / set-top box on your local
network. macOS menu bar app + Tampermonkey userscript or browser extension.

English · [中文](README.md)

> 🤖 **Agents and contributors: read [AGENTS.md](AGENTS.md) first.** It is the
> single source of truth for the codebase: module layout, network topology,
> known pitfalls, API contract, and release pipeline.

## What it does

The Bilibili web player has no native "cast to TV" button — only the mobile and
tablet apps do. This project adds one with two pieces:

1. A **browser-side entry point** — either a Tampermonkey userscript or a
   browser extension — that injects a Cast button on every Bilibili video page;
2. A **local casting backend**: the stable track is the macOS menu bar app;
   `crossplatform/` adds the Wails2 cross-platform backend, desktop client,
   and Docker daemon mode.

> This tool only casts public videos that the signed-in user already has
> permission to watch. **It does not bypass paywalls, region locks, member
> content, DRM, or login.** Bangumi, members-only, and DRM-protected content
> show an explicit "unsupported" toast.

The stable track runs on macOS 13+, both Apple Silicon and Intel. The cross-platform backend track is documented in [`crossplatform/README.md`](crossplatform/README.md) and currently targets Windows / Linux Wails2 desktop builds plus Docker deployments.

### Three quality tiers

| Tier | Source | Max resolution | Mac must stay running? |
|---|---|---|---|
| **Standard** (default) | Bilibili `playurl?platform=html5` single-file MP4 | 720P | No — TV streams direct from Bilibili CDN |
| **HD** (experimental) | Bilibili TV-signed playurl, returns FLV | 1080P | No — TV streams direct from Bilibili CDN |
| **Ultra** | `dash.video[]+audio[]` muxed locally via ffmpeg | Native (4K / HDR) | Yes — Mac actively transcodes for the TV |

Switchable from the menu bar. Ultra mode needs ffmpeg — the .app **bundles it**
inside `.app/Contents/Resources/`, so you don't need to install it separately.

## Install

### Homebrew (recommended)

```bash
brew tap jianzhoujz/tap
brew install --cask bilicast
```

Upgrade / uninstall:

```bash
brew upgrade --cask bilicast
brew uninstall --cask bilicast
```

### Manual

Grab `BiliCast-VERSION.dmg` from
[GitHub Releases](https://github.com/jianzhoujz/bilicast/releases). Open the
DMG and drag `BiliCast.app` onto the `Applications` shortcut.

### Cross-platform / Docker backend (in development)

```bash
cd crossplatform

# Go daemon for local or server use
go run ./cmd/bilicastd

# Docker daemon
docker compose up --build
# Console: http://127.0.0.1:18787/console

# Wails2 desktop app
go install github.com/wailsapp/wails/v2/cmd/wails@v2.10.2
wails build -tags wails
```

The cross-platform backend keeps the same HTTP API and can be used by the Tampermonkey userscript, browser extension, and HTTP console. Every Wails build uses `http://127.0.0.1:18787/console` for control pages, and that console uses the dedicated API prefix `/api/bilicast` with local token bootstrap. The Wails desktop client currently focuses on Windows / Linux; the tray/native menu shows or hides the main window and can quit the app, while the Wails home page redirects to that console.

### Browser-side entry point

Install either option.

#### Tampermonkey userscript

1. Install [Tampermonkey](https://www.tampermonkey.net/) in your browser.
2. Click here → **[install latest userscript](https://github.com/jianzhoujz/bilicast/raw/main/userscript/bilicast-helper.user.js)**
   (Tampermonkey detects the `.user.js` extension and pops the install dialog.)
3. To upgrade later, click the same link again — Tampermonkey will prompt for
   the update.

If the one-click install doesn't trigger, fall back to: open
[the script source](userscript/bilicast-helper.user.js) → copy everything →
Tampermonkey → New script → paste → save.

#### Browser extension (Chrome / Edge developer mode)

1. Open `chrome://extensions` or `edge://extensions`.
2. Enable Developer Mode.
3. Click `Load unpacked`.
4. Pick the repository's [`extension/`](extension/) directory.
5. Click the extension icon, paste the Pairing Token from the menu bar app, and save it.

## First launch

The app is **not signed with an Apple Developer ID**. First launch may be
blocked by Gatekeeper with "cannot verify the developer" or "app is damaged".

If you trust the source:

1. Open `System Settings → Privacy & Security`
2. Find the "BiliCast was blocked" notice and click `Open Anyway`
3. Try launching again

If that still doesn't work, remove the quarantine flag manually:

```bash
xattr -dr com.apple.quarantine /Applications/BiliCast.app
```

## Usage

### 1. Start the menu bar app

`open -a BiliCast` or launch from Spotlight. A `📺` icon appears in the
menu bar. Clicking it shows:

- Service running status
- Control API endpoint
- **Pairing Token** with a Copy button
- **Quality mode** (default: Standard)
- Discovered DLNA device list
- Current cast session (only when something is playing)
- "Check for updates" / "GitHub repo"
- Quit

### 2. Pair the token (first time)

Menu bar → Copy Token. The first time you click Cast on a Bilibili page the
userscript prompts you to paste it. After that every request is authenticated
automatically.

### 3. Cast

Open any Bilibili video page (`https://www.bilibili.com/video/BV...`). A pink
`Cast` button appears bottom-right:

1. Click it → device picker opens.
2. Pick the target TV (if the list is empty, hit "Rescan").
3. Userscript collects stream candidates (mp4 / flv / dash) → POSTs to
   `/api/cast`.
4. Mac picks the best stream for your selected quality tier → creates a session
   → drives the TV via DLNA AVTransport.

Once playing, the menu bar shows the current title, target device, and quality
tier. Click "Stop Casting" to end immediately.

### 4. Switching quality

Menu bar → Quality Mode dropdown. Each option shows pros, limits, and notes
inline.

- **Don't quit the app while in Ultra mode** — the stream is muxed live by
  ffmpeg on your Mac; quitting the app cuts the stream.
- **HD mode falls back to Standard** if the TV-signed call fails (e.g.
  Bilibili rotated their app secret), with a toast notification.

## Network and files

| Purpose | Listen address |
|---|---|
| Control API (userscript) | `127.0.0.1:18787`, loopback only |
| Stream proxy (TV) | `0.0.0.0:18788`, only `/stream/<sessionId>/video` |

| Item | Path |
|---|---|
| Config (token) | `~/Library/Application Support/BiliCast/config.json`, mode 0600 |
| Logs | macOS unified logging, subsystem `local.bilicast` |

Tail logs:

```bash
log stream --predicate 'subsystem == "local.bilicast"' --info --debug
```

## Troubleshooting

| Symptom | Likely cause / fix |
|---|---|
| No Cast button on Bilibili page | Userscript disabled, or URL doesn't match (bangumi pages show an "unsupported" toast on click) |
| Red toast "BiliCast not detected" | Menu bar app not running / port 18787 in use |
| `TOKEN_INVALID` | Token mismatch — copy fresh from menu, paste via Tampermonkey menu "Set BiliCast Token" |
| Empty device list | TV off / TV DLNA disabled / different Wi-Fi / firewall blocks multicast |
| `UNSUPPORTED_CONTENT` | No castable candidates available; usually paid or DRM content |
| `DLNA_SET_URI_FAILED` / `DLNA_PLAY_FAILED` | TV rejected the URL / format / codec; check SOAP detail in logs |
| Ultra-mode stream stalls after a few seconds | Mac went to sleep or switched Wi-Fi; keep Mac awake |

## Development

Engineering reference: [AGENTS.md](AGENTS.md) — repo layout, build commands,
module boundaries, SSDP / SOAP details, ffmpeg integration, update checker,
known pitfalls, release workflow.

```bash
# browser-side syntax / extension bridge smoke test
node --test tests/extension-smoke.test.mjs

# cross-platform backend tests
(cd crossplatform && go test ./... && go test -tags wails .)

# CI coverage
# - PR Checks: browser scripts, Go backend, Docker smoke
# - Wails Build: Windows amd64, Linux amd64
# - Native macOS App Build: existing Swift native app universal zip / dmg
# - Docker Image CI: multi-arch GHCR image
# - Release: tag creation, GitHub Release, desktop, native macOS app, and Docker build fan-out

cd macos

# compile
swift build

# run without bundling
swift run BiliCastApp

# build .app (auto-downloads and bundles ffmpeg; use a proxy in mainland China)
./build.sh

# build DMG
./package-dmg.sh

# skip ffmpeg download; rely on system ffmpeg at runtime
BILICAST_SKIP_FFMPEG=1 ./build.sh
```

## License

MIT — see [LICENSE](LICENSE).
