# BiliCastHelper

![macOS](https://img.shields.io/badge/macOS-13.0%2B-black)
![Apple Silicon](https://img.shields.io/badge/Apple%20Silicon-supported-brightgreen)
![Intel](https://img.shields.io/badge/Intel-supported-brightgreen)
![Release](https://img.shields.io/github/v/release/jianzhoujz/bilicast)

把 B 站网页版视频投到局域网的 DLNA 电视、盒子或投影仪。Mac 菜单栏 App + Tampermonkey 用户脚本。

[English](README.en.md) · 中文

> 🤖 **AI 协作 Agent / 贡献者请先看 [AGENTS.md](AGENTS.md)**：项目唯一面向 AI 阅读的入口文档，含模块划分、踩坑笔记、API 设计、发布流程。

## 介绍

哔哩哔哩网页版没有原生的"投屏到电视"按钮（手机 / 平板 App 才有）。本工具用：

1. 一个 **浏览器端入口**，可选 Tampermonkey 用户脚本或浏览器扩展，在 B 站视频页右下角注入"投屏"按钮；
2. 一个 **Mac 菜单栏 App**，本机起 HTTP 控制 API + 局域网视频代理 + DLNA/UPnP 设备扫描和控制。

> 仅用于把当前账号本就有权访问的普通公开视频投到自有局域网设备。**不绕过会员、版权、区域、登录或 DRM 限制**，番剧、付费内容、DRM 内容都会明确提示"暂不支持"。

支持 macOS 13+，Apple Silicon 和 Intel 都行。

### 三档清晰度

|档位|来源|清晰度上限|是否需要 Mac 一直开着|
|---|---|---|---|
|**标准**（默认）|B 站 `playurl?platform=html5` 单文件 MP4|720P|否，电视直连 B 站 CDN|
|**高清**（实验性）|B 站 TV 接口签名拿 FLV|1080P|否，电视直连 B 站 CDN|
|**极清**|`dash.video[]+audio[]` + 本机 ffmpeg 实时合流|与原片一致（4K / HDR）|是，电视播放期间 Mac 必须开机运行|

可在菜单栏切换。极清依赖 ffmpeg —— App 已经把 ffmpeg 打包在 `.app/Contents/Resources/` 里，**无需额外安装**。

## 安装

### Homebrew（推荐）

```bash
brew tap jianzhoujz/tap
brew install --cask bilicast
```

更新 / 卸载：

```bash
brew upgrade --cask bilicast
brew uninstall --cask bilicast
```

### 手动安装

从 [GitHub Releases](https://github.com/jianzhoujz/bilicast/releases) 下载 `BiliCastHelper-VERSION.dmg`，打开后将 `BiliCastHelper.app` 拖到 `Applications` 快捷方式上。

### 浏览器端入口

二选一安装即可。

#### Tampermonkey 用户脚本

1. 浏览器装 [Tampermonkey](https://www.tampermonkey.net/)
2. 打开 [`userscript/bilicast-helper.user.js`](userscript/bilicast-helper.user.js) 全文，新建脚本粘贴并保存
3. 后续脚本更新就重新粘贴一次

#### 浏览器扩展（Chrome / Edge 开发者模式）

1. 打开 `chrome://extensions` 或 `edge://extensions`
2. 开启"开发者模式"
3. 点"加载已解压的扩展程序"
4. 选择仓库里的 [`extension/`](extension/) 目录
5. 点扩展图标，粘贴并保存菜单栏 App 里的 Pairing Token

## 首次启动

当前应用**没有 Apple Developer ID 签名**。首次启动时 macOS 可能提示"无法验证开发者"或"应用已损坏"。

如果你确认来源可信，先试：

1. 打开 `系统设置 -> 隐私与安全性`
2. 看到 BiliCastHelper 被阻止的提示，点 `仍要打开`
3. 再启动一次

如果仍然不行，移除 quarantine 标记：

```bash
xattr -dr com.apple.quarantine /Applications/BiliCastHelper.app
```

## 使用说明

### 1. 启动 Mac App

`open -a BiliCastHelper` 或从启动台打开。菜单栏会出现 `📺` 图标，点开看到：

- 服务运行状态
- 控制 API 地址
- **Pairing Token**（复制按钮）
- **清晰度模式**（默认"标准"）
- DLNA 设备列表
- 当前投屏会话（投屏后才显示）
- "检查更新"、"GitHub 主页"
- 退出

### 2. 配对 Token（首次）

菜单栏 → 复制 Token → 在 B 站视频页第一次点投屏时浏览器会弹 `prompt`，把 token 粘进去保存。后续投屏自动带 token，不会再问。

### 3. 投屏

打开任意 B 站视频页（`https://www.bilibili.com/video/BV...`），右下角有粉色 `投屏` 按钮：

1. 点按钮 → 弹设备选择框
2. 选目标电视（如果列表空，点"重新扫描"）
3. 用户脚本提取候选流（mp4 / flv / dash）→ POST `/api/cast`
4. Mac 端按你设的清晰度模式挑流 → 建 session → 通过 DLNA 控制电视开始播

投屏后菜单栏会显示当前会话标题、目标设备、清晰度档，点"停止投屏"立即停。

### 4. 切换清晰度

菜单栏 → "清晰度模式" → 三档下拉选。每档下面有详细说明：优点、限制、注意事项。

- **极清模式期间不要退出 Mac App**：流是 Mac 实时 remux 推给电视的，App 一关电视就断流。
- **高清模式失败时会自动降级**到标准模式，并 toast 提示。

## 网络与文件

| 用途 | 监听 |
|---|---|
| 控制 API（用户脚本调用） | `127.0.0.1:18787`，仅本机 |
| 流代理（电视访问） | `0.0.0.0:18788`，仅 `/stream/<sessionId>/video` |

| 内容 | 路径 |
|---|---|
| 配置（含 token） | `~/Library/Application Support/BiliCastHelper/config.json` 权限 0600 |
| 日志 | macOS 统一日志，subsystem `local.bilicast-helper` |

看日志：

```bash
log stream --predicate 'subsystem == "local.bilicast-helper"' --info --debug
```

## 故障排查

| 现象 | 可能原因 / 解决 |
|---|---|
| B 站页面没有"投屏"按钮 | 用户脚本未启用 / 没匹配到当前 URL（番剧页第一版只提示不支持） |
| 红色 toast"未检测到 BiliCastHelper" | 菜单栏 App 没启动 / 18787 端口被占 |
| `TOKEN_INVALID` | token 复制错了，去菜单栏重新复制再用 Tampermonkey 菜单"设置 BiliCast Token"重粘 |
| 设备列表空 | 电视关了 / 电视 DLNA 关了 / 不同 Wi-Fi / 防火墙拦多播 |
| `UNSUPPORTED_CONTENT` | 当前视频拿不到任何可投候选；可能是会员 / DRM 内容 |
| `DLNA_SET_URI_FAILED` / `DLNA_PLAY_FAILED` | TV 不接受当前 URL 格式或编码；看日志里的 SOAP 响应 detail |
| 极清档投屏后过几秒卡住 | Mac 进入睡眠或者切了 Wi-Fi；保持 Mac 唤醒 |

## 开发与贡献

完整工程速查见 [AGENTS.md](AGENTS.md)，含：仓库布局、常用命令、网络拓扑、模块边界、SSDP / SOAP 实现、ffmpeg 集成、UpdateChecker、踩过的坑、发布流程。

```bash
# 浏览器端语法 / 扩展桥接 smoke test
node --test tests/extension-smoke.test.mjs

cd macos

# 编译
swift build

# 直接跑（不打包）
swift run BiliCastApp

# 打 .app（自动下载并内置 ffmpeg；国内加代理）
./build.sh

# 出 DMG
./package-dmg.sh

# 跳过 ffmpeg 下载，依赖系统 ffmpeg
BILICAST_SKIP_FFMPEG=1 ./build.sh
```

## License

MIT —— 见 [LICENSE](LICENSE)。
