import Foundation
import Network
import BiliCastCore

final class ProxyConnection: @unchecked Sendable {
    private let connection: NWConnection
    private let queue: DispatchQueue
    private let sessions: StreamSessionStore
    private let ffmpegPath: String?
    private var buffer = Data()
    private var selfRetain: ProxyConnection?
    private var finished = false

    private static let maxHeaderBytes = 16 * 1024
    private static let chunkSize = 64 * 1024
    private static let headerTerminator = Data([0x0D, 0x0A, 0x0D, 0x0A])

    private static let allowedUpstreamResponseHeaders: Set<String> = [
        "content-type", "content-length", "content-range",
        "accept-ranges", "last-modified", "etag",
    ]

    init(
        connection: NWConnection,
        queue: DispatchQueue,
        sessions: StreamSessionStore,
        ffmpegPath: String?
    ) {
        self.connection = connection
        self.queue = queue
        self.sessions = sessions
        self.ffmpegPath = ffmpegPath
    }

    func start() {
        selfRetain = self
        connection.stateUpdateHandler = { [self] state in
            switch state {
            case .ready:
                self.readHeaders()
            case .failed(let err):
                Log.http.debug("proxy conn failed: \(String(describing: err), privacy: .public)")
                self.finish()
            case .cancelled:
                self.releaseRetain()
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        connection.cancel()
    }

    private func releaseRetain() {
        connection.stateUpdateHandler = nil
        selfRetain = nil
    }

    // MARK: - Request reading

    private func readHeaders() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [self] data, _, isComplete, error in
            if let error = error {
                Log.http.debug("proxy recv error: \(String(describing: error), privacy: .public)")
                self.finish(); return
            }
            if let data = data, !data.isEmpty {
                self.buffer.append(data)
            }
            if let sep = self.buffer.range(of: Self.headerTerminator) {
                let headBytes = self.buffer.subdata(in: 0..<sep.lowerBound)
                guard let parsed = HTTPParser.parseHead(headBytes) else {
                    self.writeStatusOnly(400, reason: "Bad Request"); return
                }
                self.dispatch(parsed: parsed)
                return
            }
            if self.buffer.count > Self.maxHeaderBytes {
                self.writeStatusOnly(431, reason: "Request Header Fields Too Large"); return
            }
            if isComplete {
                self.finish(); return
            }
            self.readHeaders()
        }
    }

    private func dispatch(parsed: ParsedRequestHead) {
        let queue = self.queue
        Task { [self] in
            await self.handle(parsed: parsed)
            queue.async { self.finish() }
        }
    }

    private func handle(parsed: ParsedRequestHead) async {
        let comps = parsed.path
            .split(separator: "/", omittingEmptySubsequences: false)
            .map(String.init)
        guard comps.count == 4, comps[0].isEmpty, comps[1] == "stream", comps[3] == "video" else {
            await writeStatusOnlyAsync(404, reason: "Not Found")
            return
        }
        let sessionId = comps[2]
        guard let session = sessions.get(sessionId) else {
            await writeStatusOnlyAsync(404, reason: "Session Not Found")
            return
        }

        guard parsed.method == "GET" || parsed.method == "HEAD" else {
            await writeStatusOnlyAsync(405, reason: "Method Not Allowed")
            return
        }

        Log.http.info("proxy \(parsed.method, privacy: .public) session=\(session.id, privacy: .public) tier=\(session.tier.rawValue, privacy: .public)")

        switch session.kind {
        case .direct(let upstreamURL, let upstreamHeaders):
            await handleDirect(parsed: parsed, upstream: upstreamURL, upstreamHeaders: upstreamHeaders)
        case .muxedDash(let videoURL, let audioURL, let upstreamHeaders):
            await handleMuxedDash(parsed: parsed, videoURL: videoURL, audioURL: audioURL, upstreamHeaders: upstreamHeaders)
        }
    }

    // MARK: - Direct (mp4 / flv) path

    private func handleDirect(
        parsed: ParsedRequestHead,
        upstream upstreamURL: URL,
        upstreamHeaders: [String: String]
    ) async {
        var upstream = URLRequest(url: upstreamURL)
        upstream.httpMethod = parsed.method
        upstream.timeoutInterval = 12
        for (k, v) in upstreamHeaders {
            upstream.setValue(v, forHTTPHeaderField: k)
        }
        for (k, v) in parsed.headers {
            let lk = k.lowercased()
            if lk == "range" || lk == "if-range" {
                upstream.setValue(v, forHTTPHeaderField: k)
            }
        }

        if parsed.method == "HEAD" {
            do {
                var headReq = upstream
                headReq.httpMethod = "HEAD"
                let (_, response) = try await URLSession.shared.data(for: headReq)
                guard let http = response as? HTTPURLResponse else {
                    await writeStatusOnlyAsync(502, reason: "Bad Gateway"); return
                }
                try await writeHeaders(from: http, body: Data())
            } catch {
                Log.http.debug("proxy HEAD failed: \(String(describing: error), privacy: .public)")
                await writeStatusOnlyAsync(502, reason: "Bad Gateway")
            }
            return
        }

        do {
            let (bytes, response) = try await URLSession.shared.bytes(for: upstream)
            guard let http = response as? HTTPURLResponse else {
                await writeStatusOnlyAsync(502, reason: "Bad Gateway"); return
            }
            try await writeHeaders(from: http, body: nil)

            var chunk = Data()
            chunk.reserveCapacity(Self.chunkSize)
            for try await byte in bytes {
                chunk.append(byte)
                if chunk.count >= Self.chunkSize {
                    try await sendAsync(chunk)
                    chunk.removeAll(keepingCapacity: true)
                }
            }
            if !chunk.isEmpty {
                try await sendAsync(chunk)
            }
        } catch is CancellationError {
            // client disconnected
        } catch {
            Log.http.debug("proxy stream error: \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: - Muxed DASH (ffmpeg) path

    private func handleMuxedDash(
        parsed: ParsedRequestHead,
        videoURL: URL,
        audioURL: URL,
        upstreamHeaders: [String: String]
    ) async {
        guard let ffmpegPath else {
            Log.http.error("muxed session but ffmpeg not available")
            await writeStatusOnlyAsync(503, reason: "ffmpeg unavailable")
            return
        }

        // MPEG-TS is a continuous stream — Range/HEAD don't make sense. Be lenient with HEAD.
        if parsed.method == "HEAD" {
            let head =
                "HTTP/1.1 200 OK\r\n" +
                "Content-Type: video/mp2t\r\n" +
                "Accept-Ranges: none\r\n" +
                "Connection: close\r\n\r\n"
            try? await sendAsync(Data(head.utf8))
            return
        }

        let muxer = FFmpegMuxer(
            ffmpegPath: ffmpegPath,
            videoURL: videoURL,
            audioURL: audioURL,
            headers: upstreamHeaders
        )
        do {
            try muxer.start()
        } catch {
            Log.http.error("ffmpeg start failed: \(String(describing: error), privacy: .public)")
            await writeStatusOnlyAsync(502, reason: "ffmpeg start failed")
            return
        }

        let head =
            "HTTP/1.1 200 OK\r\n" +
            "Content-Type: video/mp2t\r\n" +
            "Accept-Ranges: none\r\n" +
            "Cache-Control: no-store\r\n" +
            "Connection: close\r\n\r\n"
        do {
            try await sendAsync(Data(head.utf8))
            for try await chunk in muxer.bytes() {
                try await sendAsync(chunk)
            }
        } catch is CancellationError {
            // client disconnected
        } catch {
            Log.http.debug("muxed stream ended: \(String(describing: error), privacy: .public)")
        }
        muxer.stop()
    }

    // MARK: - Common

    private func writeHeaders(from http: HTTPURLResponse, body: Data?) async throws {
        var head = "HTTP/1.1 \(http.statusCode) \(HTTPResponse.reasonPhrase(for: http.statusCode))\r\n"
        var sawAcceptRanges = false
        for (key, value) in http.allHeaderFields {
            let kStr = String(describing: key)
            let lk = kStr.lowercased()
            if Self.allowedUpstreamResponseHeaders.contains(lk) {
                if lk == "accept-ranges" { sawAcceptRanges = true }
                head += "\(kStr): \(value)\r\n"
            }
        }
        if !sawAcceptRanges {
            head += "Accept-Ranges: bytes\r\n"
        }
        head += "Connection: close\r\n\r\n"
        try await sendAsync(Data(head.utf8))
        if let body = body, !body.isEmpty {
            try await sendAsync(body)
        }
    }

    private func writeStatusOnly(_ code: Int, reason: String) {
        let msg = "HTTP/1.1 \(code) \(reason)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(msg.utf8), completion: .contentProcessed { [self] _ in
            self.finish()
        })
    }

    private func writeStatusOnlyAsync(_ code: Int, reason: String) async {
        let msg = "HTTP/1.1 \(code) \(reason)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        try? await sendAsync(Data(msg.utf8))
    }

    private func sendAsync(_ data: Data) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { err in
                if let err = err { cont.resume(throwing: err) } else { cont.resume() }
            })
        }
    }
}
