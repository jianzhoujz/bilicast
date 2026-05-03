# BiliCastHelper Cross-Platform Backend

This directory contains the Wails2-based cross-platform backend track.

## Runtime targets

- **Wails desktop client**: Windows / Linux desktop shell, built with Wails2.
- **Native desktop entry**: Windows / Linux use a tray/native-menu action surface for showing the main window, hiding the main window, and quitting the app.
- **Daemon / server mode**: `bilicastd`, a plain Go HTTP backend for local development, headless hosts, and Docker.
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

Install Wails2, then build from this directory:

```bash
go install github.com/wailsapp/wails/v2/cmd/wails@v2.10.2
wails build -tags wails
```

The desktop app starts the new HTTP API service and stream proxy, then redirects to the HTTP console for status, token, preferences, devices, and casting controls.

Desktop shell behavior:

| OS | Surface | Actions |
|---|---|---|
| Windows | tray/native-menu window surface | show window, hide window, quit app |
| Linux | tray/native-menu window surface | show window, hide window, quit app |

`HideWindowOnClose` is enabled for the Wails app, so closing the window keeps the local casting backend alive. The tray/native menu shows or hides the main window and can quit the app; token copy, device refresh, quality selection, and casting controls stay in the HTTP console.

## Docker

Docker mode is for headless hosts. The compose file publishes the control API on host loopback only and exposes the stream proxy to the LAN:

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

This branch establishes the cross-platform backend foundation: shared API, token/config persistence, quality preference handling, stream candidate picking, direct stream proxying with Range forwarding, DASH remux streaming through ffmpeg, Wails desktop shell actions, and Docker packaging.

Automatic SSDP discovery can be wired into `Service.RefreshDevices` next; Docker/manual deployments already support explicit renderer configuration through `BILICAST_DEVICES_JSON`.
