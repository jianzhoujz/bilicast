# BiliCastHelper Cross-Platform Backend

This directory contains the Wails2-based cross-platform backend track.

## Runtime targets

- **Wails desktop client**: Windows / Linux desktop shell, built with Wails2. Release binaries embed ffmpeg for DASH remux mode and extract it to the local app cache at runtime.
- **Native desktop entry**: Windows / Linux use a tray/native-menu action surface for showing the main window, hiding the main window, and quitting the app.
- **Daemon / server mode**: `bilicastd`, a plain Go HTTP backend for local development and headless hosts. Install `ffmpeg` on the host if you use DASH remux mode.
- **Docker mode**: containerized `bilicastd` with ffmpeg included.

## Supported clients

The backend keeps the existing HTTP API contract so the same service can be used by three client entry points:

1. `userscript/` Tampermonkey script.
2. `extension/` Chrome / Edge browser extension.
3. HTTP console served by `bilicastd` at `/console`; every Wails build uses this console for control pages, and Wails `frontend/dist` only redirects there.

## API compatibility

Control API defaults to `127.0.0.1:18787`. The canonical daemon API prefix is `/api/bilicast`; compatibility aliases under `/api` remain for existing browser clients. Responses preserve the existing envelope:

```json
{"ok":true,"data":{},"error":null}
```

Implemented endpoints:

- `GET /api/bilicast/health` — no token required.
- `GET /api/bilicast/pairing/status` — token probe.
- `GET /api/bilicast/pairing/token` — local console token bootstrap.
- `GET /api/bilicast/devices` — token required.
- `POST /api/bilicast/devices/refresh` — token required.
- `GET /api/bilicast/status` — token required.
- `GET /api/bilicast/preferences` — token required.
- `PUT /api/bilicast/preferences` — token required.
- `POST /api/bilicast/cast` — token required.
- `POST /api/bilicast/cast/stop` — token required.

Stream proxy defaults to `0.0.0.0:18788` and exposes only:

- `GET /stream/<sessionId>/video`
- `HEAD /stream/<sessionId>/video`

## Development

```bash
cd crossplatform

# unit tests + API/proxy smoke coverage
go test ./...

# daemon build
go build ./cmd/bilicastd

# Wails compile check in environments with Wails desktop deps
go test -tags wails .

# run daemon locally
go run ./cmd/bilicastd
```

## Wails2 desktop

Release archives are published from the `Wails Build` workflow on version tags:

- Windows: `BiliCastHelper-windows-amd64.zip`, containing `BiliCastHelper.exe` with embedded ffmpeg.
- Linux: `BiliCastHelper-linux-amd64.tar.gz`, containing `linux-amd64/BiliCastHelper` with embedded ffmpeg.

Install Wails2, then build from this directory when developing locally:

```bash
go install github.com/wailsapp/wails/v2/cmd/wails@v2.10.2
wails build -tags wails
```

The desktop app starts the new HTTP API service and stream proxy, then redirects to the HTTP console for status, token, preferences, devices, and casting controls. For release builds, the backend extracts embedded ffmpeg to the local app cache first, then checks sidecar paths and system PATH as fallbacks.

Desktop shell behavior:

| OS | Surface | Actions |
|---|---|---|
| Windows | tray/native-menu window surface | show window, hide window, quit app |
| Linux | tray/native-menu window surface | show window, hide window, quit app |

`HideWindowOnClose` is enabled for the Wails app, so closing the window keeps the local casting backend alive. The tray/native menu shows or hides the main window and can quit the app; token copy, device refresh, quality selection, and casting controls stay in the HTTP console.

## Docker

Docker mode is for headless hosts and includes ffmpeg in the image. The compose file publishes the control API on host loopback only and exposes the stream proxy to the LAN:

```bash
cd crossplatform
docker compose up --build
```

Published ports:

- `127.0.0.1:18787 -> container:18787` for browser clients and the daemon console on the host.
- `0.0.0.0:18788 -> container:18788` for TVs fetching `/stream/<sessionId>/video`.

Open `http://127.0.0.1:18787/console` on the host to use the control page. The console bootstraps the local pairing token, stores it in browser `localStorage`, and calls the dedicated `/api/bilicast` routes.

Important environment variables:

- `BILICAST_TOKEN` — fixed pairing token. If omitted, `/data/config.json` stores a generated token.
- `BILICAST_PUBLIC_HOST` — required for Docker; LAN `host:port` advertised to TVs, for example `192.168.1.10:18788`.
- `BILICAST_DEVICES_JSON` — optional manual DLNA renderer list for containers.
- `BILICAST_CONTROL_ADDR` — container listen address, default `0.0.0.0:18787`; compose publishes it to host `127.0.0.1` only.
- `BILICAST_PROXY_ADDR` — default `0.0.0.0:18788` in Docker.

Manual device example:

```bash
export BILICAST_DEVICES_JSON='[{"id":"tv","name":"Living Room TV","avTransportControlURL":"http://192.168.1.20:1400/MediaRenderer/AVTransport/Control","avTransportServiceType":"urn:schemas-upnp-org:service:AVTransport:1"}]'
```

## Current scope

The cross-platform backend now covers shared API, token/config persistence, quality preference handling, stream candidate picking, direct stream proxying with Range forwarding, DASH remux streaming through embedded or host ffmpeg, Wails desktop shell actions, Docker packaging, and automatic SSDP device discovery.

### SSDP device discovery

`Service.RefreshDevices` now performs automatic SSDP (M-SEARCH) discovery before falling back to `BILICAST_DEVICES_JSON`. It searches for both `MediaRenderer:1` and `AVTransport:1` targets in parallel, fetches and parses device description XMLs, and registers any DLNA renderer that exposes an AVTransport service. Discovered devices are cached until the next refresh.

If SSDP returns no devices (e.g. multicast blocked by firewall, no DLNA renderers on the network), the service falls back to the `BILICAST_DEVICES_JSON` environment variable and the `BILICAST_ALLOW_MOCK_DEVICE` mock.

### Docker multicast limitation

SSDP uses UDP multicast (`239.255.255.250:1900`), which does **not** work inside a Docker container by default — the container's network namespace isolates it from the host's multicast domain. To use SSDP discovery in Docker, you must run with `--network host`:

```bash
docker run --network host ... bilicastd
```

When using `docker compose`, add `network_mode: host` to the service definition. Note that `network_mode: host` bypasses port mappings, so the control API will be available on `127.0.0.1:18787` and the stream proxy on `0.0.0.0:18788` directly.

If `--network host` is not an option, use `BILICAST_DEVICES_JSON` to manually configure DLNA renderers — the SSDP step will be skipped when no multicast-capable network is available, and the service will fall back to env-configured devices.
