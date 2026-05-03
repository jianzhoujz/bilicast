import Foundation
import Network
import BiliCastCore

public final class ProxyServer: @unchecked Sendable {
    public enum State: Sendable {
        case starting
        case ready
        case failed(String)
        case stopped
    }

    public var onStateChange: (@Sendable (State) -> Void)?

    private let port: NWEndpoint.Port
    private let sessions: StreamSessionStore
    private let ffmpegPath: String?
    private let queue = DispatchQueue(label: "bilicast.proxy")
    private var listener: NWListener?

    public init(port: UInt16, sessions: StreamSessionStore, ffmpegPath: String?) {
        self.port = NWEndpoint.Port(rawValue: port) ?? NWEndpoint.Port(rawValue: 18788)!
        self.sessions = sessions
        self.ffmpegPath = ffmpegPath
    }

    public func start() throws {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        let l = try NWListener(using: params, on: port)
        onStateChange?(.starting)
        l.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                Log.http.info("Proxy listener ready port=\(self.port.rawValue) ffmpeg=\(self.ffmpegPath ?? "<none>", privacy: .public)")
                self.onStateChange?(.ready)
            case .failed(let err):
                Log.http.error("Proxy listener failed: \(String(describing: err), privacy: .public)")
                self.onStateChange?(.failed(String(describing: err)))
            case .cancelled:
                self.onStateChange?(.stopped)
            default:
                break
            }
        }
        l.newConnectionHandler = { [weak self] conn in
            guard let self else { return }
            ProxyConnection(
                connection: conn,
                queue: self.queue,
                sessions: self.sessions,
                ffmpegPath: self.ffmpegPath
            ).start()
        }
        l.start(queue: queue)
        self.listener = l
    }

    public func stop() {
        listener?.cancel()
        listener = nil
    }
}
