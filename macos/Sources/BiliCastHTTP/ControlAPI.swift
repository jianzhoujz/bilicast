import Foundation
import BiliCastCore

public struct CastResult: Sendable {
    public let sessionId: String
    public let deviceName: String
    public let streamUrl: URL
    public let title: String
    public let tier: String

    public init(
        sessionId: String,
        deviceName: String,
        streamUrl: URL,
        title: String,
        tier: String
    ) {
        self.sessionId = sessionId
        self.deviceName = deviceName
        self.streamUrl = streamUrl
        self.title = title
        self.tier = tier
    }
}

public struct CastRequest: Sendable {
    public let deviceId: String
    public let pageUrl: String
    public let bv: String?
    public let title: String
    public let currentTime: Double
    public let candidates: [BilibiliCast.Candidate]
}

public struct ControlAPIDeps: Sendable {
    public let getToken: @Sendable () -> String
    public let getDevices: @Sendable () -> [[String: Any]]
    public let refreshDevices: @Sendable () async -> Int
    public let getStatus: @Sendable () -> [String: Any]
    public let getPreferences: @Sendable () -> [String: Any]
    public let setPreferences: @Sendable ([String: Any]) -> [String: Any]
    public let playOnDevice: @Sendable (_ deviceId: String, _ url: URL) async throws -> Void
    public let stopOnDevice: @Sendable (_ deviceId: String) async throws -> Void
    public let castBilibili: @Sendable (_ req: CastRequest) async throws -> CastResult
    public let stopCast: @Sendable (_ deviceId: String) async throws -> Void

    public init(
        getToken: @escaping @Sendable () -> String,
        getDevices: @escaping @Sendable () -> [[String: Any]],
        refreshDevices: @escaping @Sendable () async -> Int,
        getStatus: @escaping @Sendable () -> [String: Any],
        getPreferences: @escaping @Sendable () -> [String: Any],
        setPreferences: @escaping @Sendable ([String: Any]) -> [String: Any],
        playOnDevice: @escaping @Sendable (String, URL) async throws -> Void,
        stopOnDevice: @escaping @Sendable (String) async throws -> Void,
        castBilibili: @escaping @Sendable (CastRequest) async throws -> CastResult,
        stopCast: @escaping @Sendable (String) async throws -> Void
    ) {
        self.getToken = getToken
        self.getDevices = getDevices
        self.refreshDevices = refreshDevices
        self.getStatus = getStatus
        self.getPreferences = getPreferences
        self.setPreferences = setPreferences
        self.playOnDevice = playOnDevice
        self.stopOnDevice = stopOnDevice
        self.castBilibili = castBilibili
        self.stopCast = stopCast
    }
}

public enum ControlAPI {
    public static func makeRouter(deps: ControlAPIDeps) -> Router {
        let router = Router(tokenProvider: deps.getToken)

        router.add("GET", "/api/health", requiresToken: false) { _ in
            HTTPResponse.ok([
                "app": BiliCast.appName,
                "version": BiliCast.version,
                "apiVersion": BiliCast.apiVersion,
            ])
        }

        router.add("GET", "/api/pairing/status", requiresToken: false) { req in
            let provided = req.header("X-BiliCast-Token") ?? ""
            let paired = !provided.isEmpty && constantTimeEquals(provided, deps.getToken())
            return HTTPResponse.ok(["paired": paired])
        }

        router.add("GET", "/api/devices") { _ in
            HTTPResponse.ok(["devices": deps.getDevices()])
        }

        router.add("POST", "/api/devices/refresh") { _ in
            let count = await deps.refreshDevices()
            return HTTPResponse.ok(["count": count])
        }

        router.add("GET", "/api/status") { _ in
            HTTPResponse.ok(deps.getStatus())
        }

        router.add("GET", "/api/preferences") { _ in
            HTTPResponse.ok(deps.getPreferences())
        }

        router.add("PUT", "/api/preferences") { req in
            guard let json = req.jsonBody() else {
                return .error(.init(code: .badRequest, message: "JSON body required", httpStatus: 400))
            }
            return HTTPResponse.ok(deps.setPreferences(json))
        }

        router.add("POST", "/api/cast") { req in
            guard let json = req.jsonBody(),
                  let deviceId = json["deviceId"] as? String,
                  let pageUrl = json["pageUrl"] as? String
            else {
                return .error(.init(code: .badRequest, message: "deviceId and pageUrl required", httpStatus: 400))
            }
            let castReq = CastRequest(
                deviceId: deviceId,
                pageUrl: pageUrl,
                bv: json["bv"] as? String,
                title: (json["title"] as? String) ?? "BiliCast",
                currentTime: (json["currentTime"] as? Double) ?? 0,
                candidates: BilibiliCast.parseCandidates(json["candidates"])
            )
            do {
                let r = try await deps.castBilibili(castReq)
                return HTTPResponse.ok([
                    "sessionId": r.sessionId,
                    "deviceName": r.deviceName,
                    "streamUrl": r.streamUrl.absoluteString,
                    "title": r.title,
                    "tier": r.tier,
                ])
            } catch let err as APIError {
                return .error(err)
            } catch {
                return .error(.init(code: .unknown, message: String(describing: error), httpStatus: 500))
            }
        }

        router.add("POST", "/api/cast/stop") { req in
            guard let json = req.jsonBody(),
                  let deviceId = json["deviceId"] as? String
            else {
                return .error(.init(code: .badRequest, message: "deviceId required", httpStatus: 400))
            }
            do {
                try await deps.stopCast(deviceId)
                return HTTPResponse.ok(["deviceId": deviceId])
            } catch let err as APIError {
                return .error(err)
            } catch {
                return .error(.init(code: .dlnaPlayFailed, message: String(describing: error), httpStatus: 502))
            }
        }

        // --- Test/debug endpoints --------------------------------------------

        router.add("POST", "/api/test/play-url") { req in
            guard let json = req.jsonBody(),
                  let deviceId = json["deviceId"] as? String,
                  let urlString = json["url"] as? String,
                  let url = URL(string: urlString)
            else {
                return .error(.init(code: .badRequest, message: "deviceId and url required", httpStatus: 400))
            }
            do {
                try await deps.playOnDevice(deviceId, url)
                return HTTPResponse.ok(["deviceId": deviceId, "url": urlString])
            } catch let err as APIError {
                return .error(err)
            } catch {
                return .error(.init(code: .dlnaSetUriFailed, message: String(describing: error), httpStatus: 502))
            }
        }

        router.add("POST", "/api/test/stop") { req in
            guard let json = req.jsonBody(),
                  let deviceId = json["deviceId"] as? String
            else {
                return .error(.init(code: .badRequest, message: "deviceId required", httpStatus: 400))
            }
            do {
                try await deps.stopOnDevice(deviceId)
                return HTTPResponse.ok(["deviceId": deviceId])
            } catch let err as APIError {
                return .error(err)
            } catch {
                return .error(.init(code: .dlnaPlayFailed, message: String(describing: error), httpStatus: 502))
            }
        }

        return router
    }
}
