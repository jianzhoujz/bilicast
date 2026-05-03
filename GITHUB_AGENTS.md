# GITHUB_AGENTS.md

> 面向 GitHub Copilot、Claude Code、Cursor 等 AI 编码工具的入口文档。
> 完整工程速查见 [AGENTS.md](AGENTS.md)。

## 项目定位

把 B 站网页视频投到局域网 DLNA 电视。四部分组成：

- `userscript/` — Tampermonkey 用户脚本（B 站页面注入"投屏"按钮、抽流地址）
- `extension/` — Chrome / Edge MV3 浏览器扩展（复用用户脚本逻辑，background bridge 做跨域请求）
- `macos/` — Swift 写的 macOS 菜单栏 App（薄壳，管理 bilicastd 子进程，通过 BackendClient 通信）
- `crossplatform/` — Go 跨平台后端（`pkg/backend/` 共享核心），支持 Wails2 桌面端、daemon、Docker

## 快速开始

```bash
# 跨平台后端测试
cd crossplatform && go test ./...

# 跨平台后端构建
cd crossplatform && go build ./cmd/bilicastd

# macOS App 构建（自动构建 Go 后端 + Swift 端 + 组装 .app）
cd macos && ./build.sh

# 用户脚本语法检查
node --check userscript/bilicast-helper.user.js

# 浏览器端 smoke test
node --test tests/extension-smoke.test.mjs
```

## 关键约定

### Go 后端（crossplatform/pkg/backend/）

- 零外部依赖（除标准库）
- `RefreshDevices()` 先 SSDP 扫描（3 秒超时），再 fallback 环境变量
- Docker 部署需 `--network host`（多播在容器内默认不通）
- 控制 API 前缀 `/api/bilicast`，兼容别名 `/api`

### Swift 端（macos/）

- SwiftPM，零外部依赖，**禁止**未讨论就引入新依赖
- macOS 13+ 部署目标
- 并发：跨 await 锁用 `OSAllocatedUnfairLock`，不用 `NSLock`
- NWConnection 回调**不能**用 `[weak self]`（self-retain 模式）
- 日志 subsystem `local.bilicast`，**绝不**记录 token / cookie / signed URL
- `build.sh` 自动完成：Go 后端构建 → Swift release build → 组装 .app → ad-hoc 签名 → 打包 zip
- ffmpeg 固定在 `macos/lib/ffmpeg`（125 MB，universal binary），纳入 Git 管理，构建时从 lib/ 复制

### 用户脚本 / 浏览器扩展

- 单文件，无打包工具
- 所有 UI 走 Shadow DOM 隔离 B 站 CSS
- Token 存 `GM_setValue`（用户脚本）或 `chrome.storage.local`（扩展），key `bilicast.token`
- 本地 API `http://127.0.0.1:18787`
- 设备为空时自动检查 token 有效性，失效则提示并清除旧 token
- `extension/content.js` 与 `userscript/bilicast-helper.user.js` 需保持同步

## 发布流程

```bash
cd macos
APP_VERSION=X.Y.Z ./build.sh    # 构建 .app
cd ..
git tag vX.Y.Z
git push && git push --tags
gh release create vX.Y.Z macos/build/BiliCast.app.zip --title "BiliCast X.Y.Z" --generate-notes
# 然后更新 ../homebrew-tap/Casks/bilicast.rb
```

## 反模式

- 加非必要 SwiftPM 依赖
- 日志记录敏感数据
- 控制 API 绑到 `0.0.0.0`
- NWConnection 闭包用 `[weak self]`
- 跨 await 用 `NSLock`
- 在后台线程直接改 `@Published`
