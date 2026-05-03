import Foundation
import BiliCastCore

public typealias RouteHandler = @Sendable (HTTPRequest) async -> HTTPResponse

public struct Route: Sendable {
    public let method: String
    public let path: String
    public let requiresToken: Bool
    public let handler: RouteHandler
}

public final class Router: @unchecked Sendable {
    private var routes: [Route] = []
    private let tokenProvider: @Sendable () -> String

    public init(tokenProvider: @escaping @Sendable () -> String) {
        self.tokenProvider = tokenProvider
    }

    public func add(
        _ method: String,
        _ path: String,
        requiresToken: Bool = true,
        handler: @escaping RouteHandler
    ) {
        routes.append(Route(method: method.uppercased(), path: path, requiresToken: requiresToken, handler: handler))
    }

    public func dispatch(_ req: HTTPRequest) async -> HTTPResponse {
        let matchPath = routes.filter { $0.path == req.path }
        guard !matchPath.isEmpty else {
            return .error(.init(code: .notFound, message: "Not found", httpStatus: 404))
        }
        guard let route = matchPath.first(where: { $0.method == req.method }) else {
            return .error(.init(code: .methodNotAllowed, message: "Method not allowed", httpStatus: 405))
        }
        if route.requiresToken {
            let provided = req.header("X-BiliCast-Token") ?? ""
            if provided.isEmpty {
                return .error(.init(code: .tokenMissing, message: "Missing X-BiliCast-Token header", httpStatus: 401))
            }
            if !constantTimeEquals(provided, tokenProvider()) {
                return .error(.init(code: .tokenInvalid, message: "Invalid token", httpStatus: 403))
            }
        }
        return await route.handler(req)
    }
}
