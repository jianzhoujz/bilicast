# BiliCastHelper 开发计划

> 目标：给哔哩哔哩网页版增加一个“投屏到电视”能力。  
> 形态：Tampermonkey 用户脚本 + macOS 原生菜单栏 App。  
> 使用场景：Mac 上用浏览器打开 B 站网页，点击网页里的“投屏”按钮，把普通公开视频投到局域网内支持 DLNA/UPnP 的电视、盒子或投影仪。

---

## 1. 项目定位

### 1.1 项目名称

暂定：

```text
BiliCastHelper
```

包含两个子项目：

```text
bilicast-userscript     # Tampermonkey 用户脚本
BiliCastHelper.app      # macOS 菜单栏 App / 本地投屏服务
```

### 1.2 一句话目标

在 B 站网页版播放器上注入一个“投屏”按钮，点击后把当前普通公开视频发送给 Mac 本地投屏服务，由本地服务通过 DLNA/UPnP 控制电视播放。

### 1.3 不是要做什么

第一版明确不做：

- 不复刻 B 站手机 App 官方投屏协议。
- 不绕过会员、版权、番剧、区域、DRM 或登录限制。
- 不做全站视频下载器。
- 不保证所有电视、盒子、投影都兼容。
- 不支持弹幕投屏。
- 不支持 AirPlay。
- 不支持 Chromecast。
- 不支持 Windows。
- 不做 App Store 发布版。

### 1.4 第一版支持范围

第一版只支持：

- macOS。
- Chrome / Edge / Safari 中通过 Tampermonkey 运行用户脚本。
- B 站普通公开视频页。
- 同一局域网下支持 DLNA/UPnP AVTransport 的电视、盒子或投影仪。
- 视频流能被电视直接播放，或能被本地 HTTP 代理转发给电视播放。

---

## 2. 总体架构

```text
┌───────────────────────────────────────────────┐
│                B 站网页视频页                  │
│ https://www.bilibili.com/video/BVxxxx          │
└───────────────────────────────────────────────┘
                      │
                      │ Tampermonkey 用户脚本
                      │ 注入按钮 / 读取视频信息 / 调本地 API
                      ▼
┌───────────────────────────────────────────────┐
│          http://127.0.0.1:18787                │
│          Mac 本地控制 API                      │
└───────────────────────────────────────────────┘
                      │
                      │
                      ▼
┌───────────────────────────────────────────────┐
│              BiliCastHelper.app               │
│                                               │
│  1. 菜单栏 UI                                 │
│  2. 本地 HTTP API                             │
│  3. DLNA/UPnP 设备发现                         │
│  4. DLNA AVTransport 控制                      │
│  5. B 站播放信息解析                           │
│  6. 本地流代理 / Range 转发                    │
└───────────────────────────────────────────────┘
                      │
                      │ SSDP / SOAP / HTTP Stream
                      ▼
┌───────────────────────────────────────────────┐
│             局域网电视 / 盒子 / 投影           │
│             DLNA Media Renderer               │
└───────────────────────────────────────────────┘
```

---

## 3. 推荐技术栈

### 3.1 用户脚本

```text
Tampermonkey
Vanilla JavaScript
GM_xmlhttpRequest
GM_addStyle
GM_registerMenuCommand
```

原因：

- 上手快。
- 不需要浏览器扩展打包。
- 适合快速适配 B 站网页结构变化。
- 可以通过 `GM_xmlhttpRequest` 请求 `127.0.0.1` 本地服务。

### 3.2 macOS App

推荐第一版使用：

```text
SwiftUI 菜单栏壳 + Go 本地服务核心
```

也可以先简化成：

```text
Go CLI 服务 + 后续再包 SwiftUI 菜单栏壳
```

#### 推荐方案 A：最快 MVP

```text
bilicastd：Go 后台服务
userscript：Tampermonkey
```

先不做真正的 `.app`，先用命令行启动：

```bash
./bilicastd
```

等核心链路跑通后，再做菜单栏 App。

#### 推荐方案 B：较完整 MVP

```text
BiliCastHelper.app：SwiftUI MenuBarExtra
bilicastd：Go helper，随 App 启动
```

SwiftUI 负责：

- 菜单栏图标。
- 当前服务状态。
- 已发现设备列表。
- 当前默认设备。
- 复制 pairing token。
- 开启/关闭服务。
- 查看日志。

Go 负责：

- HTTP server。
- SSDP 设备发现。
- DLNA SOAP 控制。
- 本地代理。
- B 站公开视频播放信息处理。

---

## 4. 模块拆分

### 4.1 Tampermonkey 用户脚本

路径：

```text
userscript/bilicast-helper.user.js
```

职责：

1. 检测当前页面是否为 B 站视频页。
2. 在播放器区域注入“投屏”按钮。
3. 读取当前视频信息：
   - 页面 URL。
   - BV 号。
   - 标题。
   - 当前播放进度。
   - 当前播放器中的基础播放信息。
4. 请求本地服务：
   - 检测服务是否在线。
   - 获取设备列表。
   - 发起投屏。
   - 停止投屏。
5. 展示简单 UI：
   - 未启动本地服务。
   - 未发现设备。
   - 投屏中。
   - 投屏失败原因。
6. 不在脚本内保存敏感信息。
7. 不转发完整 Cookie。
8. 不尝试绕过付费、版权或 DRM。

#### 用户脚本页面匹配

```javascript
// @match        https://www.bilibili.com/video/*
// @match        https://www.bilibili.com/list/*
// @match        https://www.bilibili.com/bangumi/play/*   // 第一版可识别但提示不支持
```

第一版只真正支持：

```text
https://www.bilibili.com/video/BVxxxx
```

番剧页第一版提示：

```text
当前内容可能受版权或 DRM 限制，第一版暂不支持。请使用 HDMI / AirPlay / 系统镜像。
```

#### 用户脚本本地 API 配置

默认 API 地址：

```text
http://127.0.0.1:18787
```

Tampermonkey 元信息：

```javascript
// @connect      127.0.0.1
// @connect      localhost
// @grant        GM_xmlhttpRequest
// @grant        GM_addStyle
// @grant        GM_registerMenuCommand
// @grant        GM_getValue
// @grant        GM_setValue
```

#### 用户脚本需要实现的函数

```javascript
function isBilibiliVideoPage()
function extractBvFromUrl(url)
function getVideoTitle()
function getCurrentTime()
function getPagePlayInfo()
function getLocalToken()
function setLocalToken(token)
function requestLocalApi(path, payload)
function injectCastButton()
function showDevicePicker(devices)
function castCurrentVideo(deviceId)
function stopCast()
function showToast(message, type)
```

#### 投屏请求示例

```json
{
  "pageUrl": "https://www.bilibili.com/video/BVxxxx",
  "bv": "BVxxxx",
  "title": "视频标题",
  "currentTime": 128.4,
  "source": "tampermonkey",
  "pagePlayInfo": {
    "optional": "第一版尽量少传，避免传 Cookie 等敏感数据"
  }
}
```

---

### 4.2 Mac 本地服务

服务名：

```text
bilicastd
```

默认监听：

```text
控制 API：127.0.0.1:18787
局域网投屏代理：0.0.0.0:18788
```

原因：

- 控制 API 只给本机用户脚本访问，不能暴露到局域网。
- 视频代理必须让电视访问，所以需要监听局域网地址。
- 代理端口只允许访问 `/stream/*`，不能做任意 URL 代理。

#### 本地服务模块

```text
cmd/bilicastd/main.go

internal/config
internal/httpapi
internal/security
internal/device
internal/dlna
internal/bilibili
internal/proxy
internal/logging
```

#### 推荐目录结构

```text
BiliCastHelper/
├── README.md
├── BiliCastHelper_PLAN.md
├── userscript/
│   └── bilicast-helper.user.js
├── macos/
│   └── BiliCastHelper/
│       ├── BiliCastHelper.xcodeproj
│       └── BiliCastHelper/
│           ├── App.swift
│           ├── MenuBarView.swift
│           ├── SettingsView.swift
│           └── HelperProcess.swift
├── bilicastd/
│   ├── go.mod
│   ├── cmd/
│   │   └── bilicastd/
│   │       └── main.go
│   └── internal/
│       ├── config/
│       ├── httpapi/
│       ├── security/
│       ├── device/
│       ├── dlna/
│       ├── bilibili/
│       ├── proxy/
│       └── logging/
└── docs/
    ├── api.md
    ├── dlna-notes.md
    ├── security.md
    └── test-plan.md
```

---

## 5. 本地 API 设计

### 5.1 通用约定

Base URL：

```text
http://127.0.0.1:18787
```

请求 Header：

```http
Content-Type: application/json
X-BiliCast-Token: <pairing-token>
```

统一响应：

```json
{
  "ok": true,
  "data": {},
  "error": null
}
```

错误响应：

```json
{
  "ok": false,
  "data": null,
  "error": {
    "code": "NO_DEVICE",
    "message": "未发现可用 DLNA 设备"
  }
}
```

### 5.2 健康检查

```http
GET /api/health
```

响应：

```json
{
  "ok": true,
  "data": {
    "app": "BiliCastHelper",
    "version": "0.1.0",
    "apiVersion": 1
  },
  "error": null
}
```

此接口可以不要求 token，用于用户脚本判断本地服务是否启动。

### 5.3 获取 pairing 状态

```http
GET /api/pairing/status
```

响应：

```json
{
  "ok": true,
  "data": {
    "paired": true
  },
  "error": null
}
```

### 5.4 获取设备列表

```http
GET /api/devices
```

响应：

```json
{
  "ok": true,
  "data": {
    "devices": [
      {
        "id": "uuid:xxxx",
        "name": "Living Room TV",
        "modelName": "DLNA Renderer",
        "manufacturer": "Sony",
        "location": "http://192.168.1.23:8008/description.xml",
        "available": true
      }
    ]
  },
  "error": null
}
```

### 5.5 刷新设备

```http
POST /api/devices/refresh
```

响应：

```json
{
  "ok": true,
  "data": {
    "count": 2
  },
  "error": null
}
```

### 5.6 发起投屏

```http
POST /api/cast
```

请求：

```json
{
  "deviceId": "uuid:xxxx",
  "pageUrl": "https://www.bilibili.com/video/BVxxxx",
  "bv": "BVxxxx",
  "title": "视频标题",
  "currentTime": 128.4,
  "source": "tampermonkey"
}
```

响应：

```json
{
  "ok": true,
  "data": {
    "sessionId": "cast_123",
    "deviceName": "Living Room TV",
    "streamUrl": "http://192.168.1.10:18788/stream/cast_123/master.mp4"
  },
  "error": null
}
```

### 5.7 停止投屏

```http
POST /api/cast/stop
```

请求：

```json
{
  "deviceId": "uuid:xxxx"
}
```

### 5.8 暂停 / 继续

```http
POST /api/cast/pause
POST /api/cast/play
```

请求：

```json
{
  "deviceId": "uuid:xxxx"
}
```

### 5.9 当前状态

```http
GET /api/status
```

响应：

```json
{
  "ok": true,
  "data": {
    "running": true,
    "currentSession": {
      "sessionId": "cast_123",
      "title": "视频标题",
      "deviceName": "Living Room TV",
      "startedAt": "2026-05-02T12:00:00+09:00"
    }
  },
  "error": null
}
```

---

## 6. DLNA / UPnP 实现计划

### 6.1 设备发现

使用 SSDP M-SEARCH。

目标地址：

```text
239.255.255.250:1900
```

搜索目标优先级：

```text
urn:schemas-upnp-org:device:MediaRenderer:1
urn:schemas-upnp-org:service:AVTransport:1
ssdp:all
```

M-SEARCH 请求示例：

```http
M-SEARCH * HTTP/1.1
HOST: 239.255.255.250:1900
MAN: "ssdp:discover"
MX: 2
ST: urn:schemas-upnp-org:device:MediaRenderer:1
```

收到响应后：

1. 读取 `LOCATION`。
2. 拉取 device description XML。
3. 解析：
   - friendlyName。
   - manufacturer。
   - modelName。
   - UDN。
   - serviceList。
4. 找到 `AVTransport` service：
   - serviceType。
   - controlURL。
   - eventSubURL。
   - SCPDURL。

### 6.2 控制播放

核心动作：

```text
SetAVTransportURI
Play
Pause
Stop
Seek
GetTransportInfo
```

第一版至少实现：

```text
SetAVTransportURI
Play
Stop
```

#### SetAVTransportURI

SOAP action：

```text
urn:schemas-upnp-org:service:AVTransport:1#SetAVTransportURI
```

参数：

```xml
<InstanceID>0</InstanceID>
<CurrentURI>http://192.168.1.10:18788/stream/cast_123/master.mp4</CurrentURI>
<CurrentURIMetaData></CurrentURIMetaData>
```

#### Play

SOAP action：

```text
urn:schemas-upnp-org:service:AVTransport:1#Play
```

参数：

```xml
<InstanceID>0</InstanceID>
<Speed>1</Speed>
```

#### Stop

SOAP action：

```text
urn:schemas-upnp-org:service:AVTransport:1#Stop
```

参数：

```xml
<InstanceID>0</InstanceID>
```

---

## 7. 本地代理设计

### 7.1 为什么需要代理

很多网页视频地址具有：

- 临时签名。
- Referer 校验。
- User-Agent 校验。
- Range 请求。
- 分片请求。
- 音视频分离。
- HTTPS 证书兼容性问题。
- 电视无法直接访问某些域名或格式。

所以 Mac 本地服务需要生成局域网可访问地址：

```text
http://<mac-lan-ip>:18788/stream/<sessionId>/video
```

电视播放的是这个本地 URL，由 Mac 负责向上游请求 B 站视频资源。

### 7.2 代理安全限制

代理服务必须限制：

- 只允许访问当前投屏 session 绑定的上游 URL。
- 不允许任意 URL 参数转发，例如禁止 `/proxy?url=...` 这种开放代理。
- 不记录敏感 URL。
- session 过期后清理。
- 只支持 GET / HEAD。
- 支持 Range。
- 限制并发连接数。
- 限制单 session 生命周期。

### 7.3 Range 支持

电视通常会发送：

```http
Range: bytes=123456-
```

代理需要转发 Range，并正确返回：

```http
HTTP/1.1 206 Partial Content
Accept-Ranges: bytes
Content-Range: bytes 123456-999999/1000000
Content-Length: 876544
Content-Type: video/mp4
```

同时需要支持：

```http
HEAD /stream/<sessionId>/video
```

### 7.4 MIME 类型

根据实际内容返回：

```text
video/mp4
video/x-matroska
application/vnd.apple.mpegurl
video/mp2t
application/dash+xml
```

第一版建议优先只支持：

```text
video/mp4
```

遇到 DASH 音视频分离、m4s 分段时，优先提示暂不支持，后续再做 remux。

---

## 8. B 站信息解析策略

### 8.1 第一版策略

第一版不做复杂逆向，只做保守解析：

1. 从 URL 提取 BV 号。
2. 从页面 DOM 获取标题。
3. 从播放器读取当前播放时间。
4. 尝试读取页面已有的公开播放信息：
   - `window.__playinfo__`
   - `window.__INITIAL_STATE__`
   - 页面中已有的 video / source 信息
5. 如果拿不到可用的单文件视频 URL，则提示不支持。

### 8.2 不支持情况

遇到以下情况直接提示：

- 当前是番剧页。
- 当前是会员内容。
- 当前是 DRM 内容。
- 当前需要额外登录鉴权。
- 当前只拿到 DASH 音视频分离流，且没有实现 remux。
- 当前视频 URL 无法被本地代理成功读取。
- 电视不支持当前编码。

提示文案：

```text
当前视频暂不支持投屏。可能原因：会员/版权/DRM、音视频分离、电视编码不兼容。建议使用 HDMI、AirPlay 或系统屏幕镜像。
```

### 8.3 后续可选增强

后续可以考虑：

- 支持 DASH 音视频分离的本地 remux。
- 使用 ffmpeg 在本地 remux 成 MP4 或 MPEG-TS。
- 支持 HLS 输出。
- 根据设备能力选择编码和封装格式。
- 通过用户手动授权方式使用浏览器侧已存在的短期播放 URL。

注意：不要绕过 DRM、付费权限或平台访问控制。

---

## 9. macOS 菜单栏 App 设计

### 9.1 菜单栏 UI

菜单项建议：

```text
BiliCastHelper
├── 状态：服务运行中
├── 默认设备：Living Room TV
├── 设备
│   ├── Living Room TV ✓
│   ├── Bedroom Projector
│   └── 重新扫描设备
├── 当前投屏
│   ├── 标题：xxx
│   ├── 停止投屏
│   └── 打开日志
├── 配对
│   ├── 复制 Token
│   └── 重置 Token
├── 设置
│   ├── 开机启动
│   ├── 代理端口
│   └── 仅允许本机控制 API
└── 退出
```

### 9.2 App 行为

启动时：

1. 启动本地 HTTP 控制 API。
2. 启动局域网投屏代理。
3. 自动扫描 DLNA 设备。
4. 生成或读取 pairing token。
5. 菜单栏显示运行状态。

退出时：

1. 停止当前投屏 session。
2. 关闭 HTTP server。
3. 清理临时 session。
4. 退出 helper 进程。

### 9.3 日志

日志级别：

```text
ERROR
WARN
INFO
DEBUG
```

日志内容要避免：

- 完整 Cookie。
- 完整签名 URL。
- 敏感 headers。

日志可以记录：

- 设备发现结果。
- DLNA 控制动作。
- 上游响应状态码。
- Range 请求区间。
- 错误码和错误原因。

---

## 10. 安全设计

### 10.1 控制 API

控制 API 只监听：

```text
127.0.0.1:18787
```

不要监听：

```text
0.0.0.0:18787
```

### 10.2 局域网代理

代理监听：

```text
0.0.0.0:18788
```

但只能访问：

```text
/stream/<sessionId>/...
```

不能提供：

```text
/proxy?url=...
```

### 10.3 Token

生成随机 token：

```text
32 bytes random，base64url 编码
```

用户脚本调用控制 API 时必须带：

```http
X-BiliCast-Token: <token>
```

`/api/health` 可以无 token。

### 10.4 Pairing 流程

第一版简单方案：

1. Mac App 菜单栏显示“复制 Token”。
2. 用户脚本首次点击投屏时提示粘贴 token。
3. 用户脚本用 `GM_setValue` 保存 token。
4. 后续请求自动带 token。

后续优化：

- 本地页面 `http://127.0.0.1:18787/pair` 展示二维码或一键授权。
- 用户脚本自动检测 pairing 状态。

---

## 11. 错误码设计

```text
SERVICE_OFFLINE       本地服务未启动
TOKEN_MISSING         缺少 token
TOKEN_INVALID         token 无效
NO_DEVICE             未发现设备
DEVICE_OFFLINE        设备不可用
UNSUPPORTED_PAGE      当前页面不支持
UNSUPPORTED_CONTENT   当前内容不支持
NO_PLAYABLE_STREAM    没有可投屏的视频流
UPSTREAM_FAILED       上游视频流请求失败
RANGE_NOT_SUPPORTED   上游不支持 Range
DLNA_SET_URI_FAILED   DLNA SetAVTransportURI 失败
DLNA_PLAY_FAILED      DLNA Play 失败
PROXY_FAILED          本地代理失败
UNKNOWN_ERROR         未知错误
```

用户侧文案要友好，例如：

```text
未检测到 BiliCastHelper，请先启动菜单栏 App。
```

```text
没有发现可用电视。请确认电视和 Mac 在同一 Wi-Fi，并开启电视的 DLNA/投屏功能。
```

```text
当前视频暂不支持投屏，建议使用 HDMI 或系统屏幕镜像。
```

---

## 12. MVP 开发阶段

### Phase 0：仓库初始化

目标：

- 建立 monorepo。
- 写 README。
- 写本计划文档。
- 确定端口、API、错误码。

产出：

```text
README.md
BiliCastHelper_PLAN.md
userscript/bilicast-helper.user.js
bilicastd/go.mod
```

验收：

- 能运行空的 Go 服务。
- 能安装空的 Tampermonkey 脚本。
- 脚本能请求 `/api/health`。

---

### Phase 1：用户脚本注入按钮

目标：

- 在 B 站视频页注入“投屏”按钮。
- 点击后检查本地服务状态。
- 本地服务未启动时给提示。

任务：

- 实现 `isBilibiliVideoPage()`。
- 实现 `extractBvFromUrl()`。
- 实现 `injectCastButton()`。
- 实现 `showToast()`。
- 实现 `requestLocalApi()`。
- 实现 `GM_getValue` / `GM_setValue` token 保存。

验收：

- 打开 B 站普通视频页，能看到按钮。
- 点击按钮可以请求本地 `/api/health`。
- 服务未启动时显示明确提示。
- 服务启动时显示设备选择入口。

---

### Phase 2：Go 本地服务基础 API

目标：

- 启动 HTTP API。
- 实现 health、status、devices mock。
- 实现 token 校验。

任务：

- `GET /api/health`
- `GET /api/status`
- `GET /api/devices`
- `POST /api/devices/refresh`
- token middleware
- 统一 JSON 响应
- 错误码

验收：

- `curl http://127.0.0.1:18787/api/health` 返回成功。
- 带 token 可以访问 devices。
- 不带 token 访问受保护接口返回 `TOKEN_MISSING`。
- token 错误返回 `TOKEN_INVALID`。

---

### Phase 3：DLNA 设备发现

目标：

- 使用 SSDP 扫描局域网 DLNA MediaRenderer。
- 解析 device description。
- 在 `/api/devices` 返回真实设备。

任务：

- 实现 M-SEARCH。
- 解析 SSDP response。
- 拉取 `LOCATION` XML。
- 解析 friendlyName、UDN、serviceList。
- 识别 AVTransport controlURL。
- 缓存设备列表。
- 添加刷新按钮。

验收：

- 能发现家里的电视/盒子/投影。
- 设备名称显示正确。
- 重复扫描不会重复添加同一设备。
- 设备离线后有合理状态。

---

### Phase 4：DLNA 播放本地测试视频

目标：

- 不接入 B 站，先投一个固定 MP4 测试 URL。
- 验证 `SetAVTransportURI` + `Play` 链路。

任务：

- 实现 SOAP client。
- 实现 `SetAVTransportURI`。
- 实现 `Play`。
- 实现 `Stop`。
- 新增测试接口：

```http
POST /api/test/play-url
```

请求：

```json
{
  "deviceId": "uuid:xxxx",
  "url": "https://example.com/test.mp4"
}
```

验收：

- 电视能播放一个公网 MP4 测试视频。
- 能停止播放。
- DLNA 错误能显示出来。
- 如果电视不支持格式，返回清晰错误。

---

### Phase 5：本地代理

目标：

- 让电视播放 Mac 本地代理出的测试视频。
- 支持 Range。

任务：

- 启动 `0.0.0.0:18788` 代理服务。
- 实现 session registry。
- 实现 `/stream/<sessionId>/video`。
- 支持 GET / HEAD。
- 支持 Range 转发。
- 返回正确 headers。
- 限制只能访问 session 内绑定 URL。

验收：

- 浏览器访问 `http://<mac-lan-ip>:18788/stream/<sessionId>/video` 能播放。
- 电视通过 DLNA 播放本地代理 URL 成功。
- 拖动进度不会立即失败。
- 代理不会接受任意 URL。

---

### Phase 6：B 站普通公开视频投屏

目标：

- 从 B 站网页发起投屏。
- 本地服务接收页面信息。
- 尝试从页面传来的信息或 URL 中拿到可播放视频流。
- 通过本地代理投给电视。

任务：

用户脚本：

- 提取 BV。
- 提取 title。
- 提取 currentTime。
- 尝试读取页面已有播放信息。
- 发起 `/api/cast`。

本地服务：

- 接收 `/api/cast`。
- 判断页面类型。
- 提取或选择可播放 stream URL。
- 创建 stream session。
- 生成局域网代理 URL。
- 调 DLNA `SetAVTransportURI`。
- 调 DLNA `Play`。
- 返回 session 信息。

验收：

- 打开 B 站普通公开视频。
- 点击投屏。
- 选择电视。
- 电视开始播放。
- 不支持的视频给明确提示。
- 不出现敏感信息日志。

---

### Phase 7：SwiftUI 菜单栏 App

目标：

- 把 Go 服务包装成 macOS 菜单栏 App。

任务：

- 创建 SwiftUI macOS App。
- 使用 `MenuBarExtra`。
- 启动/停止 `bilicastd` helper。
- 显示服务状态。
- 显示设备列表。
- 复制 token。
- 打开日志目录。
- 退出时停止 helper。

验收：

- 双击 App 后菜单栏出现图标。
- 本地服务自动启动。
- 菜单栏能看到设备。
- 能复制 token。
- 退出 App 后服务停止。

---

## 13. Codex 实现顺序建议

请按以下顺序实现，避免一开始做太多：

```text
1. 建 monorepo 和 README
2. 写 Go 服务 /api/health
3. 写用户脚本，注入按钮并请求 /api/health
4. 加 token
5. 做 devices mock
6. 做 SSDP 真扫描
7. 做 DLNA SOAP 播放公网 MP4
8. 做本地代理和 Range
9. 接 B 站普通视频页
10. 最后再做 SwiftUI 菜单栏壳
```

每一步都要能独立运行和验证。

---

## 14. 给 Codex 的具体开发提示

### 14.1 总体要求

- 先实现最小可运行版本。
- 不要一次性实现所有功能。
- 每完成一个 phase，更新 README 和测试方法。
- 所有网络错误都要有明确错误码。
- 不要在日志中打印 Cookie、完整签名 URL、Token。
- 所有接口都要有超时。
- 所有外部请求都要有合理的 User-Agent。
- 控制 API 只能监听 `127.0.0.1`。
- 代理 API 可以监听 `0.0.0.0`，但只能暴露 session URL。

### 14.2 Go 代码要求

- 使用标准库优先。
- HTTP server 使用 `net/http`。
- XML 解析使用 `encoding/xml`。
- SSDP 使用 `net` UDP。
- 日志第一版可以用 `log/slog`。
- 配置文件放到：

```text
~/Library/Application Support/BiliCastHelper/config.json
```

- 日志放到：

```text
~/Library/Logs/BiliCastHelper/
```

- token 放到配置文件里，权限尽量设为 `0600`。

### 14.3 用户脚本要求

- 不依赖打包工具。
- 单文件可直接复制到 Tampermonkey。
- UI 不要侵入太强。
- 按钮固定在播放器右上角或右侧工具区。
- 使用 Shadow DOM 或足够独立的 class name，避免污染 B 站页面。
- 失败时用 toast，不要 alert。
- token 通过菜单命令或首次弹窗录入。

### 14.4 SwiftUI App 要求

- 先做最简单菜单栏 UI。
- 使用 MenuBarExtra。
- 不要先做复杂窗口。
- helper 进程崩溃时菜单栏显示异常状态。
- 退出 App 时清理 helper。
- 后续再考虑 Launch Agent / 开机启动。

---

## 15. 测试计划

### 15.1 单元测试

Go：

- BV 号解析。
- SSDP response 解析。
- device description XML 解析。
- AVTransport service 查找。
- SOAP body 生成。
- Range header 解析。
- token 校验。

用户脚本：

- URL 匹配。
- BV 提取。
- API 请求包装。
- UI 注入不重复。

### 15.2 集成测试

- `/api/health`。
- `/api/devices`。
- SSDP 扫描。
- DLNA 播放公网 MP4。
- 本地代理播放公网 MP4。
- B 站页面点击投屏。
- 电视播放。
- 停止播放。

### 15.3 手工测试矩阵

```text
浏览器：
- Chrome
- Edge
- Safari + Tampermonkey

设备：
- Android TV
- 国产电视
- 电视盒子
- 投影仪

网络：
- Mac 和电视同一 Wi-Fi
- Mac 有线，电视 Wi-Fi
- 访客网络隔离场景
```

### 15.4 失败场景

- 本地服务未启动。
- token 错误。
- 没有发现设备。
- 设备发现但不支持 AVTransport。
- 电视拒绝播放 URL。
- B 站视频无法解析。
- 上游 403。
- 上游不支持 Range。
- 电视只请求 HEAD。
- 电视播放一段时间后断开。

---

## 16. README 第一版内容建议

README 至少包含：

```text
# BiliCastHelper

## 功能
## 当前状态
## 安装 Tampermonkey 脚本
## 启动本地服务
## 配对 token
## 使用方法
## 支持范围
## 不支持内容
## 安全说明
## 开发
## 测试
```

重要说明：

```text
本项目仅用于把用户当前有权访问的普通公开视频投到自有局域网设备。
本项目不绕过会员、版权、区域、登录或 DRM 限制。
```

---

## 17. 开发里程碑

### Milestone 1：网页按钮 + 本地服务连通

目标：

- B 站页面出现按钮。
- 点击按钮能检测本地服务。

完成标准：

- 用户脚本可安装。
- Go 服务可启动。
- `/api/health` 正常。

### Milestone 2：设备发现

目标：

- 本地服务能发现 DLNA 设备。
- 用户脚本能展示设备列表。

完成标准：

- `/api/devices` 返回真实电视。
- 网页端能选择设备。

### Milestone 3：测试视频投屏

目标：

- 能把公网 MP4 投到电视。

完成标准：

- DLNA SetURI + Play 成功。
- Stop 成功。

### Milestone 4：本地代理

目标：

- 电视播放 Mac 代理 URL。

完成标准：

- Range 正常。
- 拖动不崩。
- 非 session URL 不可访问。

### Milestone 5：B 站普通视频投屏

目标：

- B 站普通公开视频点击投屏成功。

完成标准：

- 能播放至少 3 个普通公开视频。
- 不支持内容有明确提示。

### Milestone 6：菜单栏 App

目标：

- 打包成 macOS 菜单栏工具。

完成标准：

- 双击启动。
- 菜单栏管理设备和 token。
- 退出清理。

---

## 18. 后续增强方向

暂不做，但可以预留设计：

- Chrome Extension 替代 Tampermonkey。
- Native Messaging 替代 localhost API。
- Chromecast 支持。
- AirPlay 提示或集成系统镜像入口。
- ffmpeg 本地 remux。
- 设备能力探测。
- 多清晰度选择。
- 播放进度同步。
- 遥控器控制回传。
- 历史设备记忆。
- 自动选择默认设备。
- 开机启动。
- 自动更新用户脚本。
- 图形化日志窗口。

---

## 19. 关键风险

### 19.1 B 站页面变化

风险：

- DOM 变更导致按钮注入失败。
- 全局变量变化导致播放信息读取失败。

应对：

- 用户脚本代码模块化。
- 尽量通过 URL、标准 DOM、video 元素读取基础信息。
- 不依赖过多内部变量。
- 失败时给明确提示。

### 19.2 电视兼容性

风险：

- 设备发现到了但不能播放。
- 不同厂商 DLNA 实现差异很大。
- 编码或封装不支持。

应对：

- 先支持最常见 MP4。
- 提供测试视频功能。
- 记录设备 modelName。
- 后续维护兼容列表。

### 19.3 B 站视频流格式

风险：

- DASH 音视频分离。
- m4s 分片。
- 上游鉴权。
- Range/Referer/User-Agent 要求。

应对：

- 第一版只支持能直接播放或简单代理的流。
- 不支持时降级提示。
- 后续再考虑 remux。

### 19.4 安全风险

风险：

- 本地服务被局域网其他设备控制。
- 本地代理变成开放代理。
- 日志泄露 URL 或 token。

应对：

- 控制 API 只监听 127.0.0.1。
- token 校验。
- 代理只允许 session URL。
- 敏感信息脱敏。

---

## 20. 参考资料

这些资料用于确认技术方向，开发时可重新查阅最新版文档。

- Tampermonkey 官方文档：https://www.tampermonkey.net/documentation.php
- Tampermonkey 官网：https://www.tampermonkey.net/
- Apple SwiftUI MenuBarExtra：https://developer.apple.com/documentation/SwiftUI/MenuBarExtra
- Chrome Native Messaging：https://developer.chrome.com/docs/extensions/develop/concepts/native-messaging
- UPnP AVTransport 规范：https://upnp.org/specs/av/UPnP-av-AVTransport-v3-Service-20101231.pdf
- Sony DLNA AVTransport 示例：https://github.com/sonydevworld/audio_control_api_examples/blob/master/DLNA/AVTransport/play_file.adoc

---

## 21. 可以直接给 Codex 的起始 Prompt

```text
你是一个资深 macOS + Go + 浏览器用户脚本开发者。请基于当前仓库实现 BiliCastHelper。

项目目标：
用 Tampermonkey 用户脚本给 B 站网页版视频页增加“投屏”按钮；点击后调用 Mac 本地服务；本地服务通过 DLNA/UPnP 把普通公开视频投到局域网电视。

请严格按 BiliCastHelper_PLAN.md 分阶段实现，不要一次性做完所有功能。

第一步只做 Phase 0 和 Phase 1：
1. 建立仓库目录结构。
2. 创建 bilicastd Go 服务，实现 GET /api/health。
3. 创建 userscript/bilicast-helper.user.js。
4. 用户脚本匹配 https://www.bilibili.com/video/*。
5. 用户脚本在页面注入一个“投屏”按钮。
6. 点击按钮请求 http://127.0.0.1:18787/api/health。
7. 如果服务在线，toast 显示“BiliCastHelper 已连接”。
8. 如果服务不在线，toast 显示“未检测到 BiliCastHelper，请先启动本地服务”。
9. 更新 README，写清楚如何运行 Go 服务和安装用户脚本。

限制：
- 不要实现视频解析。
- 不要实现 DLNA。
- 不要实现 macOS App。
- 不要引入复杂框架。
- Go 优先使用标准库。
- 用户脚本必须是单文件，可直接复制到 Tampermonkey。
```

---

## 22. 当前推荐的第一条命令

在空仓库中先让 Codex 执行：

```bash
mkdir -p userscript bilicastd/cmd/bilicastd bilicastd/internal/httpapi docs
touch README.md
touch userscript/bilicast-helper.user.js
touch bilicastd/cmd/bilicastd/main.go
cd bilicastd && go mod init github.com/yourname/BiliCastHelper/bilicastd
```
