import Foundation
import Network
import BiliCastCore

public final class HTTPServer: @unchecked Sendable {
    public enum State: Sendable {
        case starting
        case ready
        case failed(String)
        case stopped
    }

    public var onStateChange: (@Sendable (State) -> Void)?

    private let port: NWEndpoint.Port
    private let loopbackOnly: Bool
    private let router: Router
    private let queue: DispatchQueue
    private var listener: NWListener?

    public init(port: UInt16, loopbackOnly: Bool, router: Router, label: String = "bilicast.http") {
        self.port = NWEndpoint.Port(rawValue: port) ?? NWEndpoint.Port(rawValue: 18787)!
        self.loopbackOnly = loopbackOnly
        self.router = router
        self.queue = DispatchQueue(label: label)
    }

    public func start() throws {
        let params = NWParameters.tcp
        if loopbackOnly {
            params.requiredInterfaceType = .loopback
        }
        params.allowLocalEndpointReuse = true
        let l = try NWListener(using: params, on: port)
        onStateChange?(.starting)
        l.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                Log.http.info("HTTP listener ready port=\(self.port.rawValue) loopback=\(self.loopbackOnly)")
                self.onStateChange?(.ready)
            case .failed(let err):
                Log.http.error("HTTP listener failed: \(String(describing: err), privacy: .public)")
                self.onStateChange?(.failed(String(describing: err)))
            case .cancelled:
                self.onStateChange?(.stopped)
            default:
                break
            }
        }
        l.newConnectionHandler = { [weak self] conn in
            guard let self else { return }
            HTTPConnection(connection: conn, queue: self.queue, router: self.router).start()
        }
        l.start(queue: queue)
        self.listener = l
    }

    public func stop() {
        listener?.cancel()
        listener = nil
    }
}
