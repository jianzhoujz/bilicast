import Foundation
import AppKit
import os
import BiliCastCore
import BiliCastHTTP

/// AppState is now a thin shell that manages the Go backend daemon (bilicastd)
/// and bridges its HTTP API responses to SwiftUI. All business logic — SSDP,
/// DLNA SOAP, stream proxy, candidate picking — lives in the shared Go backend.
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

    // MARK: - Published (UI-bound)

    @Published private(set) var status: ServiceStatus = .stopped
    @Published private(set) var token: String = ""
    @Published private(set) var lastError: String?
    @Published private(set) var devices: [BackendDevice] = []
    @Published private(set) var currentSession: CurrentSessionView?
    @Published private(set) var qualityPreference: QualityPreference = .mp4Safe
    @Published private(set) var ffmpegPath: String? = nil
    @Published private(set) var ffmpegSource: FFmpeg.Source? = nil

    // MARK: - Internal state

    private let client = BackendClient()
    private var daemonProcess: Process?
    private var deviceRefreshTimer: Timer?
    private var currentToken: String = ""

    // MARK: - Lifecycle

    func start() {
        guard daemonProcess == nil else { return }
        status = .starting

        do {
            let cfg = try ConfigStore.loadOrCreate()
            self.token = cfg.token
            self.currentToken = cfg.token
            self.qualityPreference = cfg.qualityPreference

            // Locate ffmpeg for display purposes (Go backend also does this independently).
            let located = FFmpeg.locate()
            self.ffmpegPath = located?.path
            self.ffmpegSource = located?.source
            if let l = located {
                Log.app.info("ffmpeg located: \(l.path, privacy: .public) source=\(String(describing: l.source), privacy: .public)")
            } else {
                Log.app.info("ffmpeg not found; dashRemux tier will degrade")
            }

            // Start Go backend daemon.
            try startDaemon(token: cfg.token, quality: cfg.qualityPreference)

            // Initial device refresh.
            Task.detached(priority: .userInitiated) { [weak self] in
                await self?.refreshDevicesFromBackend()
            }

            startDeviceRefreshTimer()
            status = .running
            lastError = nil

            Log.app.info("BiliCast started; token=\(Log.redact(self.token), privacy: .public) preference=\(self.qualityPreference.rawValue, privacy: .public)")
        } catch {
            let msg = String(describing: error)
            self.status = .failed(msg)
            self.lastError = msg
            Log.app.error("start failed: \(msg, privacy: .public)")
        }
    }

    func stop() {
        deviceRefreshTimer?.invalidate()
        deviceRefreshTimer = nil
        daemonProcess?.terminate()
        daemonProcess?.waitUntilExit()
        daemonProcess = nil
        status = .stopped
    }

    // MARK: - Daemon management

    private func startDaemon(token: String, quality: QualityPreference) throws {
        // Locate bilicastd binary. In development it's built alongside the Swift
        // package; in production it's bundled inside the .app.
        let binaryURL: URL
        if let bundled = Bundle.main.url(forAuxiliaryExecutable: "bilicastd") {
            binaryURL = bundled
        } else {
            // Development fallback: look in the crossplatform build directory.
            let devPath = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()  // AppState.swift
                .deletingLastPathComponent()  // BiliCastApp
                .deletingLastPathComponent()  // Sources
                .deletingLastPathComponent()  // macos
                .appendingPathComponent("../crossplatform/bilicastd")
                .standardized
            binaryURL = devPath
        }

        guard FileManager.default.isExecutableFile(atPath: binaryURL.path) else {
            throw APIError(code: .serviceOffline,
                           message: "bilicastd not found at \(binaryURL.path). Build the Go backend first.",
                           httpStatus: 500)
        }

        let proc = Process()
        proc.executableURL = binaryURL
        proc.arguments = [
            "--control-addr", "127.0.0.1:\(BiliCast.controlPort)",
            "--proxy-addr", "0.0.0.0:\(BiliCast.proxyPort)",
        ]
        var env = ProcessInfo.processInfo.environment
        env["BILICAST_TOKEN"] = token
        env["BILICAST_QUALITY"] = quality.rawValue
        proc.environment = env

        // Capture stdout/stderr for debugging.
        let outPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = outPipe
        outPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty, let line = String(data: data, encoding: .utf8) {
                Log.app.debug("bilicastd: \(line.trimmingCharacters(in: .whitespacesAndNewlines), privacy: .public)")
            }
        }

        try proc.run()
        self.daemonProcess = proc

        // Give the daemon a moment to bind its ports.
        Thread.sleep(forTimeInterval: 0.5)

        Log.app.info("bilicastd started pid=\(proc.processIdentifier)")
    }

    // MARK: - Backend bridge

    private func refreshDevicesFromBackend() async {
        do {
            _ = try await client.refreshDevices(token: currentToken)
            let devs = try await client.devices(token: currentToken)
            await MainActor.run { self.devices = devs }
        } catch {
            Log.app.error("refreshDevices failed: \(String(describing: error), privacy: .public)")
        }
    }

    private func refreshStatusFromBackend() async {
        do {
            let s = try await client.status(token: currentToken)
            await MainActor.run {
                if let cs = s.currentSession {
                    // Parse startedAt and map tier.
                    let tier = QualityPreference(rawValue: cs.tier) ?? .mp4Safe
                    let startedAt = ISO8601DateFormatter().date(from: cs.startedAt) ?? Date()
                    self.currentSession = CurrentSessionView(
                        sessionId: cs.sessionId,
                        title: cs.title,
                        deviceName: cs.deviceName,
                        deviceId: cs.deviceId,
                        tier: tier,
                        startedAt: startedAt
                    )
                } else {
                    self.currentSession = nil
                }
            }
        } catch {
            // Silently ignore — status polling is best-effort.
        }
    }

    // MARK: - Public actions

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
        currentToken = new
        // Restart daemon with new token.
        stop()
        start()
    }

    func setQualityPreference(_ pref: QualityPreference) {
        qualityPreference = pref
        var cfg = (try? ConfigStore.loadOrCreate()) ?? Config(token: token)
        cfg.qualityPreference = pref
        try? ConfigStore.save(cfg)

        Task.detached { [weak self] in
            guard let self else { return }
            _ = try? await self.client.setPreferences(pref, token: self.currentToken)
        }
    }

    func refreshDevicesNow() {
        Task.detached(priority: .userInitiated) { [weak self] in
            await self?.refreshDevicesFromBackend()
        }
    }

    func stopCurrentCast() {
        guard let cs = currentSession else { return }
        Task.detached { [weak self] in
            guard let self else { return }
            _ = try? await self.client.stopCast(deviceId: cs.deviceId, token: self.currentToken)
            await MainActor.run { self.currentSession = nil }
        }
    }

    // MARK: - Timer

    private func startDeviceRefreshTimer() {
        deviceRefreshTimer?.invalidate()
        let t = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task.detached { [weak self] in
                await self?.refreshDevicesFromBackend()
                await self?.refreshStatusFromBackend()
            }
        }
        RunLoop.main.add(t, forMode: .common)
        deviceRefreshTimer = t
    }
}
