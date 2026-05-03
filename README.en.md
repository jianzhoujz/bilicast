# BiliCastHelper

![macOS](https://img.shields.io/badge/macOS-13.0%2B-black)
![Apple Silicon](https://img.shields.io/badge/Apple%20Silicon-supported-brightgreen)
![Intel](https://img.shields.io/badge/Intel-supported-brightgreen)
![Release](https://img.shields.io/github/v/release/jianzhoujz/bilicast)

Cast Bilibili web videos to a DLNA TV / projector / set-top box on your local
network. macOS menu bar app + Tampermonkey userscript.

English · [中文](README.md)

> 🤖 **Agents and contributors: read [AGENTS.md](AGENTS.md) first.** It is the
> single source of truth for the codebase: module layout, network topology,
> known pitfalls, API contract, and release pipeline.

## What it does

The Bilibili web player has no native "cast to TV" button — only the mobile and
tablet apps do. This project adds one with two pieces:

1. A **Tampermonkey userscript** that injects a Cast button on every Bilibili
   video page;
2. A **macOS menu bar app** that runs a local HTTP control API, a LAN-facing
   stream proxy, and a DLNA / UPnP discovery + control client.

> This tool only casts public videos that the signed-in user already has
> permission to watch. **It does not bypass paywalls, region locks, member
> content, DRM, or login.** Bangumi, members-only, and DRM-protected content
> show an explicit "unsupported" toast.

Runs on macOS 13+, both Apple Silicon and Intel.

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

Grab `BiliCastHelper-VERSION.dmg` from
[GitHub Releases](https://github.com/jianzhoujz/bilicast/releases). Open the
DMG and drag `BiliCastHelper.app` onto the `Applications` shortcut.

### Userscript

1. Install [Tampermonkey](https://www.tampermonkey.net/) in your browser.
2. Open [`userscript/bilicast-helper.user.js`](userscript/bilicast-helper.user.js),
   create a new userscript, paste the entire contents, save.
3. To update later, paste the new version over the old one.

## First launch

The app is **not signed with an Apple Developer ID**. First launch may be
blocked by Gatekeeper with "cannot verify the developer" or "app is damaged".

If you trust the source:

1. Open `System Settings → Privacy & Security`
2. Find the "BiliCastHelper was blocked" notice and click `Open Anyway`
3. Try launching again

If that still doesn't work, remove the quarantine flag manually:

```bash
xattr -dr com.apple.quarantine /Applications/BiliCastHelper.app
```

## Usage

### 1. Start the menu bar app

`open -a BiliCastHelper` or launch from Spotlight. A `📺` icon appears in the
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
| Config (token) | `~/Library/Application Support/BiliCastHelper/config.json`, mode 0600 |
| Logs | macOS unified logging, subsystem `local.bilicast-helper` |

Tail logs:

```bash
log stream --predicate 'subsystem == "local.bilicast-helper"' --info --debug
```

## Troubleshooting

| Symptom | Likely cause / fix |
|---|---|
| No Cast button on Bilibili page | Userscript disabled, or URL doesn't match (bangumi pages show an "unsupported" toast on click) |
| Red toast "BiliCastHelper not detected" | Menu bar app not running / port 18787 in use |
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
