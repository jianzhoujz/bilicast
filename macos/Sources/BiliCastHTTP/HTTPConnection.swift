import Foundation
import Network
import BiliCastCore

final class HTTPConnection: @unchecked Sendable {
    private let connection: NWConnection
    private let queue: DispatchQueue
    private let router: Router
    private var buffer = Data()
    private var selfRetain: HTTPConnection?
    private var finished = false

    private static let maxHeaderBytes = 16 * 1024
    private static let maxBodyBytes = 1 * 1024 * 1024
    private static let headerTerminator = Data([0x0D, 0x0A, 0x0D, 0x0A])

    init(connection: NWConnection, queue: DispatchQueue, router: Router) {
        self.connection = connection
        self.queue = queue
        self.router = router
    }

    func start() {
        selfRetain = self
        connection.stateUpdateHandler = { [self] state in
            switch state {
            case .ready:
                self.readHeaders()
            case .failed(let err):
                Log.http.debug("conn failed: \(String(describing: err), privacy: .public)")
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

    private func readHeaders() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [self] data, _, isComplete, error in
            if let error = error {
                Log.http.debug("recv error: \(String(describing: error), privacy: .public)")
                self.finish(); return
            }
            if let data = data, !data.isEmpty {
                self.buffer.append(data)
            }
            if let sep = self.buffer.range(of: Self.headerTerminator) {
                let headBytes = self.buffer.subdata(in: 0..<sep.lowerBound)
                let bodyStart = sep.upperBound
                guard let parsed = HTTPParser.parseHead(headBytes) else {
                    self.writeAndClose(.error(.init(code: .badRequest, message: "Malformed request", httpStatus: 400)))
                    return
                }
                let contentLength = Int(parsed.headers.first(where: { $0.0.lowercased() == "content-length" })?.1 ?? "") ?? 0
                if contentLength < 0 || contentLength > Self.maxBodyBytes {
                    self.writeAndClose(.error(.init(code: .payloadTooLarge, message: "Body too large", httpStatus: 413)))
                    return
                }
                let already = self.buffer.count - bodyStart
                if already >= contentLength {
                    let body = self.buffer.subdata(in: bodyStart..<(bodyStart + contentLength))
                    self.dispatch(parsed: parsed, body: body)
                } else {
                    self.readBody(parsed: parsed, bodyStart: bodyStart, expected: contentLength)
                }
                return
            }
            if self.buffer.count > Self.maxHeaderBytes {
                self.writeAndClose(.error(.init(code: .badRequest, message: "Headers too large", httpStatus: 431)))
                return
            }
            if isComplete {
                self.finish(); return
            }
            self.readHeaders()
        }
    }

    private func readBody(parsed: ParsedRequestHead, bodyStart: Int, expected: Int) {
        let need = max(1, expected - (buffer.count - bodyStart))
        connection.receive(minimumIncompleteLength: 1, maximumLength: need) { [self] data, _, isComplete, error in
            if let error = error {
                Log.http.debug("recv body error: \(String(describing: error), privacy: .public)")
                self.finish(); return
            }
            if let data = data, !data.isEmpty {
                self.buffer.append(data)
            }
            if self.buffer.count - bodyStart >= expected {
                let body = self.buffer.subdata(in: bodyStart..<(bodyStart + expected))
                self.dispatch(parsed: parsed, body: body)
                return
            }
            if isComplete {
                self.finish(); return
            }
            self.readBody(parsed: parsed, bodyStart: bodyStart, expected: expected)
        }
    }

    private func dispatch(parsed: ParsedRequestHead, body: Data) {
        let req = HTTPRequest(
            method: parsed.method,
            path: parsed.path,
            query: parsed.query,
            httpVersion: parsed.httpVersion,
            headers: parsed.headers,
            body: body
        )
        let router = self.router
        Task { [self] in
            let res = await router.dispatch(req)
            Log.http.info("\(req.method, privacy: .public) \(req.path, privacy: .public) -> \(res.status)")
            self.queue.async {
                self.writeAndClose(res)
            }
        }
    }

    private func writeAndClose(_ response: HTTPResponse) {
        var head = "HTTP/1.1 \(response.status) \(response.reason)\r\n"
        var hasContentLength = false, hasConnection = false
        for (k, v) in response.headers {
            head += "\(k): \(v)\r\n"
            let lk = k.lowercased()
            if lk == "content-length" { hasContentLength = true }
            if lk == "connection" { hasConnection = true }
        }
        if !hasContentLength { head += "Content-Length: \(response.body.count)\r\n" }
        if !hasConnection { head += "Connection: close\r\n" }
        head += "\r\n"
        var out = Data(head.utf8)
        out.append(response.body)
        connection.send(content: out, completion: .contentProcessed { [self] _ in
            self.finish()
        })
    }
}
