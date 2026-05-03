import Foundation
import AppKit
import os
import BiliCastCore
import BiliCastHTTP
import BiliCastDLNA

@MainActor
final class AppState: ObservableObject {
    enum ServiceStatus: Equatable {
        case stopped
        case starting
        case running
        case failed(String)
    }

    struct CurrentSessionView: Equatable {
        let sessionId: String
        let title: String
        let deviceName: String
        let deviceId: String
        let tier: QualityPreference
        let startedAt: Date
    }

    @Published private(set) var status: ServiceStatus = .stopped
    @Published private(set) var token: String = ""
    @Published private(set) var lastError: String?
    @Published private(set) var devices: [DLNADevice] = []
    @Published private(set) var currentSession: CurrentSessionView?
    @Published private(set) var qualityPreference: QualityPreference = .mp4Safe
    @Published private(set) var ffmpegPath: String?
    @Published private(set) var ffmpegSource: FFmpeg.Source?

    private let tokenStore = ThreadSafeBox<String>("")
    private let preferenceStore = OSAllocatedUnfairLock<QualityPreference>(initialState: .mp4Safe)
    private let ffmpegPathStore = OSAllocatedUnfairLock<String?>(initialState: nil)
    private var controlServer: HTTPServer?
    private var proxyServer: ProxyServer?
    private var deviceRefreshTimer: Timer?

    let sessions = StreamSessionStore()

    private let currentSessionBox = OSAllocatedUnfairLock<CurrentSessionView?>(initialState: nil)

    func start() {
        guard controlServer == nil else { return }
        do {
            let cfg = try ConfigStore.loadOrCreate()
            self.token = cfg.token
            self.tokenStore.set(cfg.token)
            self.qualityPreference = cfg.qualityPreference
            self.preferenceStore.withLock { $0 = cfg.qualityPreference }

            let located = FFmpeg.locate()
            self.ffmpegPath = located?.path
            self.ffmpegSource = located?.source
            self.ffmpegPathStore.withLock { $0 = located?.path }
            if let l = located {
                Log.app.info("ffmpeg located: \(l.path, privacy: .public) source=\(String(describing: l.source), privacy: .public)")
            } else {
                Log.app.info("ffmpeg not found; dashRemux tier will degrade")
            }

            let tokenStore = self.tokenStore
            let preferenceStore = self.preferenceStore
            let ffmpegPathStore = self.ffmpegPathStore
            let discovery = DLNADiscovery.shared
            let registry = discovery.registry
            let sessions = self.sessions
            let currentSessionBox = self.currentSessionBox
            weak var weakSelf = self

            let deps = ControlAPIDeps(
                getToken: { tokenStore.get() },
                getDevices: { registry.all().map { $0.toJSON() } },
                refreshDevices: { await discovery.refresh() },
                getStatus: {
                    var out: [String: Any] = [
                        "running": true,
                        "deviceCount": registry.all().count,
                        "qualityPreference": preferenceStore.withLock({ $0 }).rawValue,
                        "ffmpegAvailable": ffmpegPathStore.withLock({ $0 }) != nil,
                    ]
                    if let cs = currentSessionBox.withLock({ $0 }) {
                        out["currentSession"] = [
                            "sessionId": cs.sessionId,
                            "title": cs.title,
                            "deviceId": cs.deviceId,
                            "deviceName": cs.deviceName,
                            "tier": cs.tier.rawValue,
                            "startedAt": ISO8601DateFormatter().string(from: cs.startedAt),
                        ]
                    } else {
                        out["currentSession"] = NSNull()
                    }
                    return out
                },
                getPreferences: {
                    [
                        "qualityPreference": preferenceStore.withLock({ $0 }).rawValue,
                        "qualityPreferenceOptions": QualityPreference.allCases.map { $0.rawValue },
                        "ffmpegAvailable": ffmpegPathStore.withLock({ $0 }) != nil,
                    ]
                },
                setPreferences: { json in
                    if let raw = json["qualityPreference"] as? String,
                       let pref = QualityPreference(rawValue: raw) {
                        preferenceStore.withLock { $0 = pref }
                        if var cfg = try? ConfigStore.loadOrCreate() {
                            cfg.qualityPreference = pref
                            try? ConfigStore.save(cfg)
                        }
                        Task { @MainActor in
                            weakSelf?.qualityPreference = pref
                        }
                    }
                    return [
                        "qualityPreference": preferenceStore.withLock({ $0 }).rawValue,
                        "ffmpegAvailable": ffmpegPathStore.withLock({ $0 }) != nil,
                    ]
                },
                playOnDevice: { deviceId, url in
                    guard let dev = registry.get(id: deviceId) else {
                        throw APIError(code: .deviceOffline,
                                       message: "Device not found: \(deviceId)",
                                       httpStatus: 404)
                    }
                    try await AVTransportClient(device: dev).playFromURL(url)
                },
                stopOnDevice: { deviceId in
                    guard let dev = registry.get(id: deviceId) else {
                        throw APIError(code: .deviceOffline,
                                       message: "Device not found: \(deviceId)",
                                       httpStatus: 404)
                    }
                    try await AVTransportClient(device: dev).stop()
                },
                castBilibili: { req in
                    guard let dev = registry.get(id: req.deviceId) else {
                        throw APIError(code: .deviceOffline,
                                       message: "Device not found: \(req.deviceId)",
                                       httpStatus: 404)
                    }
                    let preference = preferenceStore.withLock { $0 }
                    let ffmpegAvailable = ffmpegPathStore.withLock { $0 } != nil
                    guard let pick = BilibiliCast.pick(
                        from: req.candidates,
                        preference: preference,
                        ffmpegAvailable: ffmpegAvailable
                    ) else {
                        throw APIError(
                            code: .unsupportedContent,
                            message: ffmpegAvailable
                                ? "暂不支持当前视频。所有候选都为空（可能是会员/版权/DRM 内容）。"
                                : "暂不支持当前视频。可能仅有 DASH 流，请装 ffmpeg 或选'标准'清晰度。",
                            httpStatus: 415
                        )
                    }
                    guard let lanIP = NetworkInfo.primaryIPv4() else {
                        throw APIError(code: .proxyFailed,
                                       message: "无法获取 Mac 局域网 IP",
                                       httpStatus: 500)
                    }
                    // Build session per pick.
                    let session: StreamSession
                    switch pick.selection {
                    case .direct(let url, _, _):
                        session = sessions.createDirect(
                            upstream: url,
                            headers: BilibiliCast.upstreamHeaders,
                            title: req.title,
                            tier: pick.tier,
                            ttl: 6 * 3600
                        )
                    case .muxedDash(let videoURL, let audioURL, _, _):
                        session = sessions.createMuxedDash(
                            videoURL: videoURL,
                            audioURL: audioURL,
                            headers: BilibiliCast.upstreamHeaders,
                            title: req.title,
                            ttl: 6 * 3600
                        )
                    }
                    guard let streamURL = URL(string:
                        "http://\(lanIP):\(BiliCast.proxyPort)/stream/\(session.id)/video"
                    ) else {
                        sessions.remove(session.id)
                        throw APIError(code: .proxyFailed,
                                       message: "构建代理 URL 失败",
                                       httpStatus: 500)
                    }
                    let client = AVTransportClient(device: dev)
                    do {
                        try? await client.stop()
                        try await client.setURI(streamURL)
                        try await client.play()
                    } catch let e as AVTransportClient.SOAPError {
                        sessions.remove(session.id)
                        let code: APIErrorCode = e.action == "SetAVTransportURI"
                            ? .dlnaSetUriFailed
                            : .dlnaPlayFailed
                        throw APIError(code: code, message: e.description, httpStatus: 502)
                    } catch {
                        sessions.remove(session.id)
                        throw APIError(code: .dlnaPlayFailed,
                                       message: String(describing: error),
                                       httpStatus: 502)
                    }
                    let view = CurrentSessionView(
                        sessionId: session.id,
                        title: req.title,
                        deviceName: dev.name,
                        deviceId: dev.id,
                        tier: pick.tier,
                        startedAt: Date()
                    )
                    currentSessionBox.withLock { $0 = view }
                    Task { @MainActor in
                        if currentSessionBox.withLock({ $0?.sessionId }) == view.sessionId {
                            weakSelf?.currentSession = view
                        }
                    }
                    Log.app.info("cast started session=\(session.id, privacy: .public) tier=\(pick.tier.rawValue, privacy: .public) device=\(dev.name, privacy: .public)")
                    return CastResult(
                        sessionId: session.id,
                        deviceName: dev.name,
                        streamUrl: streamURL,
                        title: req.title,
                        tier: pick.tier.rawValue
                    )
                },
                stopCast: { deviceId in
                    guard let dev = registry.get(id: deviceId) else {
                        throw APIError(code: .deviceOffline,
                                       message: "Device not found: \(deviceId)",
                                       httpStatus: 404)
                    }
                    try? await AVTransportClient(device: dev).stop()
                    if let cs = currentSessionBox.withLock({ $0 }), cs.deviceId == deviceId {
                        sessions.remove(cs.sessionId)
                        currentSessionBox.withLock { $0 = nil }
                        Task { @MainActor in weakSelf?.currentSession = nil }
                    }
                }
            )

            let router = ControlAPI.makeRouter(deps: deps)
            let httpServer = HTTPServer(
                port: BiliCast.controlPort,
                loopbackOnly: true,
                router: router
            )
            httpServer.onStateChange = { [weak self] (s: HTTPServer.State) in
                DispatchQueue.main.async {
                    guard let self else { return }
                    switch s {
                    case .starting: self.status = .starting
                    case .ready:
                        self.status = .running
                        self.lastError = nil
                    case .failed(let m):
                        self.status = .failed(m)
                        self.lastError = m
                    case .stopped:
                        self.status = .stopped
                    }
                }
            }
            try httpServer.start()
            self.controlServer = httpServer

            let ps = ProxyServer(port: BiliCast.proxyPort, sessions: sessions, ffmpegPath: located?.path)
            ps.onStateChange = { (state: ProxyServer.State) in
                if case .failed(let msg) = state {
                    Log.app.error("Proxy server failed: \(msg, privacy: .public)")
                }
            }
            try ps.start()
            self.proxyServer = ps

            Log.app.info("BiliCast starting; token=\(Log.redact(self.token), privacy: .public) preference=\(self.qualityPreference.rawValue, privacy: .public)")

            Task.detached(priority: .userInitiated) {
                _ = await DLNADiscovery.shared.refresh()
            }
            startDeviceRefreshTimer()
        } catch {
            let msg = String(describing: error)
            self.status = .failed(msg)
            self.lastError = msg
            Log.app.error("start failed: \(msg, privacy: .public)")
        }
    }

    func stop() {
        controlServer?.stop()
        controlServer = nil
        proxyServer?.stop()
        proxyServer = nil
        deviceRefreshTimer?.invalidate()
        deviceRefreshTimer = nil
        status = .stopped
    }

    func copyToken() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(token, forType: .string)
    }

    func resetToken() {
        let new = TokenGenerator.generate()
        var cfg = (try? ConfigStore.loadOrCreate()) ?? Config(token: new)
        cfg.token = new
        do { try ConfigStore.save(cfg) } catch {
            Log.app.error("save config failed: \(String(describing: error), privacy: .public)")
        }
        token = new
        tokenStore.set(new)
    }

    func setQualityPreference(_ pref: QualityPreference) {
        qualityPreference = pref
        preferenceStore.withLock { $0 = pref }
        var cfg = (try? ConfigStore.loadOrCreate()) ?? Config(token: token)
        cfg.qualityPreference = pref
        try? ConfigStore.save(cfg)
    }

    func refreshDevicesNow() {
        Task.detached(priority: .userInitiated) { [weak self] in
            _ = await DLNADiscovery.shared.refresh()
            self?.reloadDevices()
        }
    }

    nonisolated func reloadDevices() {
        let snapshot = DLNADiscovery.shared.registry.all()
        Task { @MainActor in self.devices = snapshot }
    }

    func stopCurrentCast() {
        guard let cs = currentSession else { return }
        Task.detached { [weak self] in
            guard let self else { return }
            if let dev = DLNADiscovery.shared.registry.get(id: cs.deviceId) {
                try? await AVTransportClient(device: dev).stop()
            }
            self.sessions.remove(cs.sessionId)
            self.currentSessionBox.withLock { $0 = nil }
            await MainActor.run { self.currentSession = nil }
        }
    }

    private func startDeviceRefreshTimer() {
        deviceRefreshTimer?.invalidate()
        let t = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.reloadDevices()
        }
        RunLoop.main.add(t, forMode: .common)
        deviceRefreshTimer = t
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            self?.reloadDevices()
        }
    }
}
