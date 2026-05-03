import Foundation
import os
import BiliCastCore

public enum FFmpeg {
    public enum Source: Sendable, Equatable {
        case bundled
        case system
    }

    public struct Located: Sendable, Equatable {
        public let path: String
        public let source: Source
    }

    public static func locate() -> Located? {
        // 1) Bundle-shipped binary (build.sh copies it into Contents/Resources/ffmpeg).
        if let bundleURL = Bundle.main.url(forResource: "ffmpeg", withExtension: nil),
           FileManager.default.isExecutableFile(atPath: bundleURL.path) {
            return Located(path: bundleURL.path, source: .bundled)
        }
        // 2) System paths.
        let candidates = [
            "/opt/homebrew/bin/ffmpeg",
            "/usr/local/bin/ffmpeg",
            "/opt/local/bin/ffmpeg",
            "/usr/bin/ffmpeg",
        ]
        for p in candidates where FileManager.default.isExecutableFile(atPath: p) {
            return Located(path: p, source: .system)
        }
        // 3) `which ffmpeg` fallback.
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        proc.arguments = ["ffmpeg"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = nil
        do {
            try proc.run()
            proc.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let s = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !s.isEmpty, FileManager.default.isExecutableFile(atPath: s) {
                return Located(path: s, source: .system)
            }
        } catch {
            // ignore
        }
        return nil
    }
}

/// Spawns ffmpeg to remux DASH (separate video + audio m4s) into a single MPEG-TS stream.
/// Pipes stdout to an AsyncThrowingStream of byte chunks.
public final class FFmpegMuxer: @unchecked Sendable {
    private let ffmpegPath: String
    private let videoURL: URL
    private let audioURL: URL
    private let headers: [String: String]

    private let process = Process()
    private let stdoutPipe = Pipe()
    private let stderrPipe = Pipe()
    private let stopped = OSAllocatedUnfairLock<Bool>(initialState: false)

    public init(
        ffmpegPath: String,
        videoURL: URL,
        audioURL: URL,
        headers: [String: String]
    ) {
        self.ffmpegPath = ffmpegPath
        self.videoURL = videoURL
        self.audioURL = audioURL
        self.headers = headers
    }

    public func start() throws {
        let headerLine: String
        if headers.isEmpty {
            headerLine = ""
        } else {
            headerLine = headers
                .map { "\($0.key): \($0.value)" }
                .joined(separator: "\r\n") + "\r\n"
        }

        process.executableURL = URL(fileURLWithPath: ffmpegPath)
        var args = [
            "-loglevel", "warning",
            "-hide_banner",
            "-y",
        ]
        if !headerLine.isEmpty {
            args.append(contentsOf: ["-headers", headerLine])
        }
        args.append(contentsOf: [
            "-i", videoURL.absoluteString,
        ])
        if !headerLine.isEmpty {
            args.append(contentsOf: ["-headers", headerLine])
        }
        args.append(contentsOf: [
            "-i", audioURL.absoluteString,
            "-map", "0:v:0",
            "-map", "1:a:0",
            "-c", "copy",
            "-bsf:a", "aac_adtstoasc",
            "-f", "mpegts",
            "-flush_packets", "1",
            "pipe:1",
        ])
        process.arguments = args
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        // Drain stderr (logging-only). If we don't drain, ffmpeg will block on a full pipe.
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let d = handle.availableData
            if d.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            if let s = String(data: d, encoding: .utf8) {
                Log.http.debug("ffmpeg: \(s.prefix(400), privacy: .public)")
            }
        }

        Log.http.info("ffmpeg start: video=\(self.videoURL.absoluteString, privacy: .public) audio=\(self.audioURL.absoluteString, privacy: .public)")
        try process.run()
    }

    public func stop() {
        let already = stopped.withLock { v -> Bool in
            if v { return true }
            v = true
            return false
        }
        if already { return }
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil
        if process.isRunning {
            process.terminate()
        }
    }

    /// Yields stdout byte chunks until the subprocess exits or the consumer cancels.
    public func bytes() -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    continuation.finish()
                    handle.readabilityHandler = nil
                } else {
                    continuation.yield(data)
                }
            }
            continuation.onTermination = { [weak self] _ in
                self?.stop()
            }
        }
    }
}
