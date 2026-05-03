# AGENTS.md

> 这份文档是给 AI 编程助手（Claude Code、Cursor、Copilot 等）和后续维护者看的工程速查。  
> 用户文档见 [README.md](README.md)；项目原始规划见 [BiliCastHelper_PLAN.md](BiliCastHelper_PLAN.md)。

## 一句话定位

把 B 站网页视频投到局域网 DLNA 电视的小工具。两部分：

- `userscript/` —— Tampermonkey 用户脚本（B 站页面注入"投屏"按钮、抽流地址）
- `extension/` —— 浏览器扩展（Chrome / Edge MV3），复用同一份内容脚本能力，通过 background bridge 做跨域请求与 token 存储
- `macos/` —— 纯 Swift 写的 macOS 菜单栏 App（本地 HTTP 控制 API + 流代理 + DLNA 控制）
- `crossplatform/` —— Wails2 + Go 跨平台后端路线，支持 Wails 桌面客户端、Go daemon、Docker 部署

**没有 Xcode 工程文件、没有外部依赖、纯 SwiftPM + bash。** 跟 `Projects/demo/input-indicator` 同一种工程风格。

## 仓库结构

```
bilicast/
├── README.md                          # 用户向
├── AGENTS.md                          # 本文档
├── BiliCastHelper_PLAN.md             # 原始规划（Go 版，存档参考）
├── userscript/
│   └── bilicast-helper.user.js        # 单文件，可直接粘进 Tampermonkey
├── extension/
│   ├── manifest.json                  # Chrome / Edge MV3 扩展入口
│   ├── background.js                  # storage + GM_xmlhttpRequest 等价桥接
│   ├── content.js                     # 与 userscript 内容保持同步
│   ├── popup.html
│   └── popup.js                       # Token 设置弹窗
├── tests/
│   └── extension-smoke.test.mjs       # 浏览器端 smoke tests
├── crossplatform/
│   ├── pkg/backend/                   # 跨平台 Go 后端：API、token/config、proxy、DLNA SOAP、candidate pick、SSDP
│   ├── cmd/bilicastd/                 # headless daemon / Docker 入口
│   ├── frontend/dist/                 # Wails2 内置 UI 静态文件
│   ├── Dockerfile
│   ├── docker-compose.yml
│   └── wails.json
└── macos/
    ├── Package.swift                  # SwiftPM，4 个 module，零依赖
    ├── build.sh                       # 构建 Go 后端 + Swift 端 → .app bundle → 自签
    ├── fetch-ffmpeg.sh                # ffmpeg 下载脚本（缓存到 lib/）
    ├── lib/ffmpeg                     # ffmpeg universal binary（125 MB，Git 管理）
    ├── .gitignore                     # 忽略 .build/ build/
    ├── Sources/
    │   ├── BiliCastCore/              # 常量、错误码、token、config、log、网卡
    │   ├── BiliCastHTTP/              # BackendClient（HTTP 调用 bilicastd 子进程）+ 流代理
    │   ├── BiliCastDLNA/              # SSDP + 描述解析 + AVTransport SOAP（保留，不再被 BiliCastApp 依赖）
    │   └── BiliCastApp/               # @main + MenuBarExtra UI + AppState（管理 bilicastd 子进程）
    └── build/BiliCast.app       # 构建产物
```

## 常用命令

### Mac 端（开发）

```bash
cd macos

# 调试 / 联调
swift build                                              # 调试编译
swift run BiliCastApp                                    # 直接跑（不打包）
pkill -f BiliCastApp                                     # 强制停掉

# 出 .app
swift build -c release --arch arm64 --arch x86_64       # universal 二进制
./build.sh                                               # 上面 + 组装 .app + 自签
open build/BiliCast.app                            # 启动菜单栏 App
```

### 用户脚本 / 浏览器扩展

```bash
node --check userscript/bilicast-helper.user.js          # 用户脚本语法检查
node --check extension/background.js                     # 扩展 background 语法检查
node --check extension/popup.js                          # 扩展 popup 语法检查
node --test tests/extension-smoke.test.mjs               # manifest / bridge / 注入 smoke tests
```

用户脚本无打包步骤，单文件粘到 Tampermonkey 即可。

浏览器扩展无打包步骤，Chrome / Edge 开发者模式选择 `extension/` 目录加载即可。**`extension/content.js` 与 `userscript/bilicast-helper.user.js` 需保持同步**——改完用户脚本后必须把内容复制一份到 `extension/content.js`，然后跑 smoke test 验证。

### 跨平台后端

```bash
cd crossplatform

go test ./...                         # 后端单测 + API/proxy smoke
go build ./cmd/bilicastd              # daemon 构建
go test -tags wails .                 # Wails2 绑定编译检查
go run ./cmd/bilicastd
```

Wails2 构建：`wails build -tags wails`。Wails 桌面端当前聚焦 Windows / Linux，通过 `BuildShellMenu(app)` 注册托盘或原生应用菜单语义；托盘/原生菜单提供显示、隐藏主窗口与退出应用。所有 Wails 版本使用新的本地 HTTP API 服务作为控制端，Wails 首页只跳转到 `bilicastd` 的 `/console`。

Docker：`cd crossplatform && docker compose up --build`。compose 只把控制 API 发布到宿主机 `127.0.0.1:18787`，流代理 `18788` 面向局域网；Docker/daemon 后台控制页是 `http://127.0.0.1:18787/console`，canonical API 前缀是 `/api/bilicast`；容器部署必须设置 `BILICAST_PUBLIC_HOST=<LAN-IP>:18788`，需要固定设备时用 `BILICAST_DEVICES_JSON` 注入 DLNA renderer。

### GitHub Actions CI

GitHub Actions 拆成多条 workflow：

- `.github/workflows/pr-checks.yml`：PR / feature 分支检查，覆盖浏览器脚本、crossplatform Go 后端、Docker build smoke。
- `.github/workflows/ci-wails-build.yml`：Wails2 桌面端自动构建，产出 Windows amd64 exe、Linux amd64 tar.gz 与 sha256。
- `.github/workflows/macos-native-app-build.yml`：现有 Swift 原生 macOS App 自动打包，产出 universal zip / dmg 与 sha256；这是原生 App，和 Wails2 macOS 无关。
- `.github/workflows/ci-docker-build.yml`：Docker 多架构镜像构建，tag / release 时推送 GHCR。
- `.github/workflows/release.yml`：手动发版入口，自动解析/创建 tag、创建 Release，并 fan-out 调用 Wails、原生 macOS App 与 Docker 构建。

### 端到端探针（无需电视）

```bash
TOKEN=$(python3 -c "import json; print(json.load(open('$HOME/Library/Application Support/BiliCast/config.json'))['token'])")

# 健康
curl http://127.0.0.1:18787/api/bilicast/health | python3 -m json.tool

# 设备
curl -H "X-BiliCast-Token: $TOKEN" http://127.0.0.1:18787/api/bilicast/devices | python3 -m json.tool
curl -X POST -H "X-BiliCast-Token: $TOKEN" http://127.0.0.1:18787/api/bilicast/devices/refresh

# 代理：拒绝所有非 session 路径
curl -i http://127.0.0.1:18788/                          # 404
curl -i http://127.0.0.1:18788/stream/cast_xxx/video     # 404 Session Not Found
```

### 看日志

```bash
log stream --predicate 'subsystem == "local.bilicast"' --info --debug
```

或者打开 Console.app，过滤 subsystem 同上。

## 工具链要求

- **Swift 5.9+**（实测 6.3.1 OK）
- **macOS 13+** 部署目标（`MenuBarExtra` 在 macOS 13 才有；`OSAllocatedUnfairLock` 也是 macOS 13+）
- **零外部 SwiftPM 依赖**。新增依赖必须先讨论；不要为了便利引入。

## 网络拓扑（必须知道）

| 用途 | 监听 | 备注 |
|---|---|---|
| 控制 API | `127.0.0.1:18787` | **只**走 loopback，靠 `NWParameters.requiredInterfaceType = .loopback` 约束 |
| 流代理 | `0.0.0.0:18788` | 局域网可达，**只**暴露 `/stream/<sessionId>/video`，绝不开放任意 URL 代理 |
| SSDP | UDP 多播 `239.255.255.250:1900` | BSD sockets 直接发，不走 NWConnection |

## 文件系统

| 类型 | 路径 | 备注 |
|---|---|---|
| Config（含 token） | `~/Library/Application Support/BiliCast/config.json` | 权限 0600 |
| 日志 | macOS 统一日志，subsystem `local.bilicast` | 不写文件 |

## 核心架构事实

### HTTP 服务器（自写，基于 NWListener）

- 每请求关连接（HTTP/1.0 风格 `Connection: close`），简化，不做 keep-alive
- HTTP 解析在 `BiliCastHTTP/HTTPParser.swift`：先 `\r\n\r\n` 找头尾，再按 `Content-Length` 收 body
- 上限：header 16KB，body 1MB
- 所有控制 API 响应套统一信封：

```json
{"ok": true,  "data": {...}, "error": null}
{"ok": false, "data": null,  "error": {"code": "...", "message": "..."}}
```

错误码枚举见 `BiliCastCore/APIError.swift`，新增直接加 case，**不要散字符串**。

### `HTTPConnection` 和 `ProxyConnection` 的 self-retain 模式

> ⚠️ 这是踩过的坑，必须了解。

NWConnection 不会被任何外部对象持有，只被回调闭包捕获。**用 `[weak self]` 会让回调里 self 永远 nil**，症状：客户端请求超时、`CLOSE_WAIT` 堆积。

正确写法：连接对象自持有 `selfRetain = self`，状态进入 `.cancelled` 时 `selfRetain = nil`。已存在代码就是这种写法，不要改回 weak。

### DLNA 设备发现

- M-SEARCH 连发 2 次（150ms 间隔），降低丢包概率
- 并行发两个 ST：`urn:schemas-upnp-org:device:MediaRenderer:1` + `urn:...:service:AVTransport:1`
- 描述 XML 用 `XMLParser` 走 SAX，**只**取顶层 `<device>` 的 friendlyName/UDN/serviceList，忽略 `<deviceList>` 里的嵌入设备
- AVTransport 的 service type（可能是 `:1` `:2` `:3`）从描述里取，保留进 `DLNADevice.avTransportServiceType`，SOAP 调用时用真实版本号

Go 跨平台后端（`crossplatform/pkg/backend/ssdp.go`）实现了完全相同的 SSDP 逻辑：M-SEARCH 双发送（150ms 间隔）、双 ST 并行搜索、LOCATION 去重、SAX 流式解析 device description XML、相对/绝对 controlURL 解析，零外部依赖。`RefreshDevices()` 先 SSDP 扫描（3 秒超时），扫描不到 fallback 到 `BILICAST_DEVICES_JSON` 环境变量。

### DLNA SOAP

- 顺序：**stop（best-effort，忽略错误）→ SetAVTransportURI → Play**
- SOAPACTION 头格式必须是 `"<serviceType>#<actionName>"`（带引号）
- Content-Type: `text/xml; charset="utf-8"`
- 实现见 `BiliCastDLNA/AVTransportClient.swift`

### 投屏数据流（v1）

1. 用户脚本 `gatherCandidates()` 收集候选：
   - `__playinfo__.data.durl[].url`（原生页面单文件 MP4，少见）
   - `__playinfo__.data.dash.video[]/audio[].baseUrl`（DASH，常见）
   - `playurl?fnval=0&qn=120` + `?fnval=1&qn=120` fallback（**当前的主要 v1 路径，720P 封顶**）
2. POST `/api/cast` → `{deviceId, candidates: [...]}`
3. Mac 选 `kind == "mp4"` 中 quality 最高的（`BilibiliCast.pickStream()`）
4. 建 `StreamSession`，6 小时 TTL，绑定上游 URL + Referer/UA 头
5. 拼局域网 URL `http://<lanIP>:18788/stream/<sessionId>/video`
6. 调 DLNA SOAP 三连
7. `ProxyConnection` 转发 Range/If-Range，按 64KB chunk 流式回写

### 三档清晰度（架构占位，分阶段实现）

| 档位 | 来源 | 当前状态 | 路径关键点 |
|---|---|---|---|
| **mp4Safe** | `playurl?platform=html5&fnval=0/1` | ✅ 实现 | 720P 封顶，零依赖 |
| **flvTV** | TV 签名 `playurl`（appkey + MD5(params+appsec)）| 🔲 计划 | 1080P FLV，appsec 会被 B 站换，长期维护税 |
| **dashRemux** | `dash.video[]+audio[]` + ffmpeg | 🔲 计划 | 任意清晰度，依赖 ffmpeg 二进制 |

**用户脚本同时收集三档候选；Mac 端按用户偏好挑。** 任一档不可用时 fallback 链：dashRemux → flvTV → mp4Safe。降级要给 toast 通知。

## 编码规范

### Swift

- 标准库优先，**禁止**未讨论就引入 SwiftPM 依赖
- 模块边界：用 `public` 暴露，模块内 `internal` 默认
- 并发：跨 `await` 的锁用 `OSAllocatedUnfairLock`，**不要**用 `NSLock`（Swift 6 严格并发会报错）
- Sendable：闭包标 `@Sendable`，跨线程类用 `@unchecked Sendable` + 内部加锁
- 日志：`Log.app/.http/.dlna` 来自 `BiliCastCore.Logging`
- **绝对不能日志记录**：完整 token、Cookie、签名 URL、appsec、MD5 sign
- @MainActor：UI 状态只在 main 改；后台线程通过 `Task { @MainActor }` hop

### 用户脚本

- 单文件，无打包工具
- 所有 UI 走 Shadow DOM (`#bilicast-host`) 隔离 B 站 CSS
- 失败用 toast，**不要 alert**
- Tampermonkey token 放 `GM_setValue/GM_getValue`，key `bilicast.token`
- 浏览器扩展 token 放 `chrome.storage.local`，通过 `background.js` 消息桥读写同一个 key
- 本地 API：`http://127.0.0.1:18787`（Tampermonkey 已加 `@connect 127.0.0.1`；扩展已加 host permission）
- B 站 API：`https://api.bilibili.com/...`（Tampermonkey 已加 `@connect api.bilibili.com`；扩展已加 host permission）
- 失败有降级链：mp4720 fallback → 失败时清晰错误码 + 用户能看懂的中文提示

## 常见坑

### NWConnection 用 `[weak self]` 静默挂掉

见上面 self-retain 段。新写连接类一定遵循同样模式。

### macOS 多播

未签名 / 未 sandbox 的 .app 跑多播是 OK 的。一旦上 App Sandbox 就需要 `com.apple.security.network.multicast`（要 Apple 审批）。**v1 不开 sandbox**。

### `ControlAPIDeps` 闭包不在 main

闭包在 HTTP 串行 queue 上跑，不要直接改 SwiftUI `@Published`。要改 UI：`Task { @MainActor }` 或 `MainActor.run { }`。读跨线程状态用 `OSAllocatedUnfairLock` / `ThreadSafeBox`。

### 描述 XML 里 `controlURL` 可能是相对路径

用 `URL(string: relative, relativeTo: descriptionLocation)?.absoluteURL`，**不要**手拼字符串。

### B 站 `platform=html5` 硬封顶 720P

服务端策略，不是参数能绕的。1080P+ 必须走 flvTV（TV 签名）或 dashRemux（ffmpeg）。

### 私有数据脱敏

日志里出现 `\(value, privacy: .public)` 才会显示原文，否则会被 `<private>` 隐藏。Token / sign / signed URL **绝不能** `.public`。

## 端口冲突

- 18787 被占：服务起不来，`HTTPServer.State.failed` 触发，菜单栏会显示红色告警和原文
- 18788 被占：同上，但是控制 API 仍可用（degraded）；投屏会失败
- 默认端口在 `BiliCastCore/Version.swift::BiliCast.controlPort/proxyPort`

## 加新东西去哪

| 加什么 | 文件 |
|---|---|
| 新错误码 | `BiliCastCore/APIError.swift` |
| 新控制 API | `BiliCastHTTP/ControlAPI.swift` + 对应 `ControlAPIDeps` 字段 + `BiliCastApp/AppState.swift` 注入 |
| 新 SOAP action | `BiliCastDLNA/AVTransportClient.swift` |
| 新 B 站候选源 | `userscript/.../gatherCandidates()` 收集 + `BiliCastHTTP/BilibiliCast.swift` 选择 |
| 新菜单栏 UI 段 | `BiliCastApp/MenuBarView.swift`（读 `AppState`） |
| 新 config 字段 | `BiliCastCore/Config.swift`（Codable struct） |
| 新用户偏好（持久化） | `Config` 加字段 → `AppState` 暴露 → `MenuBarView` 接 UI → 用户脚本通过 `/api/preferences` 拉（如需）|

## Phase 状态

| Phase | 状态 | 备注 |
|---|---|---|
| 0 工程骨架 | ✅ | |
| 1 用户脚本注入按钮 | ✅ | |
| 2 Swift 控制 API | ✅ | NWListener + token 中间件 |
| 3 SSDP 设备发现 | ✅ | BSD sockets，双 ST 并行 |
| 4 DLNA SOAP | ✅ 代码 | 真机联调待验 |
| 5 本地代理 + Range | ✅ 代码 | curl Range 已通；真机联调待验 |
| 6 B 站投屏端到端 | ✅ 代码 | 真机联调待验 |
| 7 菜单栏 UI | ✅ 代码 | 设备列表 + 当前会话 + 重扫 + 停止 |
| 8A 清晰度偏好 UI + 持久化 | ✅ | `Config.qualityPreference` + `/api/preferences` + 菜单栏 Picker |
| 8B TV 签名 FLV（实验性）| ✅ | 用户脚本内 MD5 + `gatherFlvTV()`；appkey/appsec 内嵌 |
| 8C DASH + ffmpeg remux | ✅ | `FFmpegMuxer` + `StreamSession.muxedDash` + ProxyConnection 分支；`build.sh` 通过 `tools/fetch-ffmpeg.sh` 自动下载并打包进 `.app/Contents/Resources/ffmpeg`，可被 `Bundle.main.url(forResource:)` 找到；缺失时回退系统路径 |
| 9 检查更新 + Release 流程 | ✅ | `UpdateChecker.swift` HEAD `releases/latest`；`package-dmg.sh` → DMG → `gh release create`；homebrew tap cask |
| 10 Go 跨平台后端 SSDP | ✅ | `crossplatform/pkg/backend/ssdp.go`，从 Swift 端照搬，双 ST 并行 M-SEARCH，零外部依赖 |
| 11 macOS Swift 端瘦身 | ✅ | `BackendClient.swift` HTTP Client 层，Swift 端删除 ~2000 行业务逻辑，改为通过 bilicastd 子进程通信 |
| 12 用户脚本 token 失效检测 | ✅ | 设备为空时自动调 `/api/pairing/status` 检查 token；设备面板增加"设置 Token"按钮；token 失效时自动清除旧 token 并提示用户重新输入 |

## Phase 8 实现速查

三档已经全部接通。架构如下：

### 收集端（用户脚本 `gatherCandidates()`）

并行收集三类候选并合并到一个 `candidates: [{url, kind, quality, mime, codec}]` 数组：

| 来源 | 函数 | 产出 kind |
|---|---|---|
| `window.__playinfo__` | `gatherFromPlayinfo()` | `mp4` (durl) / `dash-video` / `dash-audio` |
| `playurl?platform=html5` | `fetchMp4Candidates()` | `mp4`（fnval=0/1，qn=120 服务端封顶 720P）|
| 签名 TV `playurl` | `fetchFlvTVCandidates()` | `flv` 或 `mp4`（appkey TV box；MD5 签名）|

**MD5 内嵌**（80 行公共领域实现）。**appkey/appsec** 写死在脚本里：
- `TV_APPKEY = '4409e2ce8ffd12b8'`
- `TV_APPSEC = '59b43e04ad6965f34319062b478f83dd'`

B 站偶尔会换 appsec，到时候这一档失效需要更新。降级链会自动兜底。

### 选择端（Mac `BilibiliCast.pick()`）

接收候选 + 用户 `QualityPreference` + ffmpeg 是否可用 → 按优先级表挑：

```
dashRemux  + ffmpeg → [dashRemux, flvTV, mp4Safe]
dashRemux  - ffmpeg → [flvTV, mp4Safe]   // 自动跳过 dashRemux
flvTV               → [flvTV, mp4Safe]
mp4Safe             → [mp4Safe]
```

无"自动"档：默认 `mp4Safe`（兼容性最好）；用户必须显式选其他档。这是有意的——避免行为不可预测。

返回 `PickResult { selection, tier }`，selection 是 `.direct(url)` 或 `.muxedDash(video, audio)`。

### 流代理（`ProxyConnection`）

在收到 `/stream/<sessionId>/video` 请求时按 `session.kind` 分支：

- `.direct(url, headers)` → `URLSession.bytes(for:)`，转发 Range/If-Range
- `.muxedDash(video, audio, headers)` → 启 `FFmpegMuxer` 子进程，stdout 喂给 NWConnection

ffmpeg 命令模板：

```bash
ffmpeg -loglevel warning -hide_banner -y \
  -headers "Referer: bilibili.com\r\nUser-Agent: ...\r\n" \
  -i <video.m4s> \
  -headers "..." \
  -i <audio.m4s> \
  -map 0:v:0 -map 1:a:0 \
  -c copy -bsf:a aac_adtstoasc \
  -f mpegts -flush_packets 1 \
  pipe:1
```

输出 MPEG-TS（Content-Type: `video/mp2t`），不支持 Range（`Accept-Ranges: none`）。stderr 排空到日志（不排空 ffmpeg 会因管道阻塞挂死）。

### ffmpeg 检测（`FFmpeg.locate()`）

启动时检测 `/opt/homebrew/bin/ffmpeg` → `/usr/local/bin/ffmpeg` → `/opt/local/bin/ffmpeg` → `/usr/bin/ffmpeg` → `which ffmpeg`。检测结果写到 `AppState.ffmpegPath`，菜单栏会显示"ffmpeg 未装"标签。

### 持久化

`Config.qualityPreference: QualityPreference` 持久到 `~/Library/Application Support/BiliCast/config.json`。Codable 用 `decodeIfPresent` 兼容旧配置：缺这个字段或者解码失败（比如旧版本写过 `"auto"`），都回退到 `.mp4Safe`。

### 控制 API 增加

```
GET  /api/preferences  → { qualityPreference, qualityPreferenceOptions, ffmpegAvailable }
PUT  /api/preferences  body: { qualityPreference: "mp4Safe"|"flvTV"|"dashRemux" }
```

`/api/status` 多了 `qualityPreference` 和 `ffmpegAvailable` 两个字段。`/api/cast` 响应多了 `tier` 字段（最终用了哪一档）。

### 已知风险

- **TV 签名 (8B)**：B 站不定期换 appsec。失效时 `fetchFlvTVCandidates` 拿不到 `code: 0`，静默返回空数组，不影响其他档；下次 8B 不可用就自动降级 8A
- **ffmpeg (8C)**：用户没装时 dashRemux 档位被自动跳过；菜单栏会显示"ffmpeg 未装"提示
- **MPEG-TS 兼容性**：极个别老电视可能不接受 mp2t 容器；如果遇到改 ffmpeg 命令为 `-f mp4 -movflags frag_keyframe+empty_moov+default_base_moof`

## 检查更新（UpdateChecker）

照搬同级目录 `input-indicator` 的实现。**不调 GitHub API（避免速率限制 + 不需要 token）**，只对 `https://github.com/jianzhoujz/bilicast/releases/latest` 发 HEAD 请求，让 GitHub 自然 302 到 `/releases/tag/v0.x.y`，从重定向后的 URL 路径里抓 tag。

`VersionNumber` 比较两边版本号；当前版本来自 `BiliCast.version`（在 `BiliCastCore/Version.swift`）。

涉及文件：
- `BiliCastApp/UpdateChecker.swift` —— 主体
- `BiliCastApp/BiliCastApp.swift` —— `AppDelegate` 持有一个 `UpdateChecker`
- `BiliCastApp/MenuBarView.swift` —— "关于" 段：版本号 + "检查更新"按钮 + "GitHub 主页" / "给个 Star"
- `BiliCastCore/Version.swift` —— `gitHubOwner/Repo/URL/LatestReleaseURL`

发版时记得：
1. `BiliCastCore/Version.swift::BiliCast.version` 同步到要发的 tag（去掉 `v` 前缀）
2. 否则用户装 v0.4.0 但 Version.swift 里还是 0.3.0，"检查更新"会一直说"有新版本"

## Release 流程

```bash
cd macos

# 1. 修订版本：BiliCast.version = "X.Y.Z"
# 2. 出 universal .app（自动下载并打包 ffmpeg）
APP_VERSION=X.Y.Z ./build.sh

# 3. 出 DMG（先复用上一步的 .app；DMG 内含拖拽到 Applications 的指引）
APP_VERSION=X.Y.Z ./package-dmg.sh
# → dist/BiliCast-X.Y.Z.dmg + 打印 sha256

# 4. 提交 + 打 tag + 推
cd ..
git tag vX.Y.Z
git push && git push --tags

# 5. 创建 GitHub Release，上传 DMG
gh release create vX.Y.Z \
  macos/dist/BiliCast-X.Y.Z.dmg \
  --title "BiliCast X.Y.Z" \
  --notes-file RELEASE_NOTES.md   # 或 --generate-notes

# 6. 更新 homebrew tap（位于同级目录 ../homebrew-tap）
SHA=$(shasum -a 256 macos/dist/BiliCast-X.Y.Z.dmg | awk '{print $1}')
# 编辑 ../homebrew-tap/Casks/bilicast.rb：
#   - version "X.Y.Z"
#   - sha256 "$SHA"
( cd ../homebrew-tap && git add Casks/bilicast.rb && git commit -m "bilicast: vX.Y.Z" && git push )
```

`tools/fetch-ffmpeg.sh` 国内必须走代理：

```bash
export https_proxy=http://127.0.0.1:7890 http_proxy=http://127.0.0.1:7890 all_proxy=socks5://127.0.0.1:7890
./build.sh
```

跳过下载（`.app` 不带 ffmpeg，运行时回退系统）：

```bash
BILICAST_SKIP_FFMPEG=1 ./build.sh
```

镜像策略（`tools/fetch-ffmpeg.sh` 内）：
- arm64：`https://www.osxexperts.net/ffmpeg711arm.zip`
- x86_64：`https://evermeet.cx/pub/ffmpeg/ffmpeg-8.1.zip`，回退 `https://evermeet.cx/ffmpeg/getrelease/zip`
- 用 `lipo -create` 合成 universal binary
- 缓存在 `Resources/ffmpeg`（gitignore），后续构建复用

镜像 / ffmpeg 版本变了，更新 `tools/fetch-ffmpeg.sh` 里的 URL 列表即可。

## Homebrew Cask 模板

仓库：`../homebrew-tap`（同 owner，名字 `homebrew-tap`，所以 `brew tap jianzhoujz/tap` 就能用）

`Casks/bilicast.rb`：

```ruby
cask "bilicast" do
  version "X.Y.Z"
  sha256 "<sha256 of DMG>"

  url "https://github.com/jianzhoujz/bilicast/releases/download/v#{version}/" \
      "BiliCast-#{version}.dmg"
  name "BiliCast"
  desc "Cast Bilibili web videos to DLNA TVs from a macOS menu bar"
  homepage "https://github.com/jianzhoujz/bilicast"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: ">= :ventura"   # macOS 13+

  app "BiliCast.app"

  uninstall quit: "local.bilicast"

  zap trash: [
    "~/Library/Application Support/BiliCast",
    "~/Library/Logs/BiliCast",
  ]
end
```

`livecheck strategy: :github_latest` 让 `brew livecheck bilicast` 自动比对最新 tag。

## 反模式（不要做）

- 加非必要 SwiftPM 依赖
- 日志记录敏感数据（token / cookie / signed URL）
- 把控制 API 绑到 `0.0.0.0`
- 代理上加 `/proxy?url=` 这种通用转发
- 在 NWConnection 闭包用 `[weak self]`
- 跨 await 用 `NSLock`
- 在 `ControlAPIDeps` 闭包里直接改 `@Published`
- 写"先做完所有功能再调试"的代码 —— 每一档/每一阶段都要能独立运行+验证

## 给后续 AI 助手的建议

- 改代码前先读 `Package.swift` 看模块划分
- 改任何网络 / 设备发现行为前，把 `Console.app` 打开过滤 `local.bilicast` 看日志
- 真机联调流程：开 .app → 复制 token → 装/更新用户脚本 → B 站视频页 → 点投屏
- 不要静默改默认端口 / token 命名 / config 路径 —— 这些是兼容契约
- 出现"客户端请求超时但服务在 LISTEN"时，第一反应去查 `[weak self]`
- 出现 SOAP 调用 500 错误时，先抓 SOAP 响应原文（`detail` 字段已包含），可能是 service version 不对（v1/v2/v3）或电视固件不规范
