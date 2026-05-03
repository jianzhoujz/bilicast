import Foundation
import BiliCastCore

/// HTTP client that talks to the Go backend daemon (bilicastd) over its control API.
/// This replaces the in-process Swift implementations of SSDP, DLNA, stream proxy,
/// and candidate picking — all of those now live in the shared Go backend.
public final class BackendClient: Sendable {
    public let baseURL: URL
    private let session: URLSession

    public init(baseURL: URL = URL(string: "http://127.0.0.1:\(BiliCast.controlPort)")!) {
        self.baseURL = baseURL
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: config)
    }

    // MARK: - Low-level request

    private func request(
        _ method: String,
        _ path: String,
        body: Data? = nil,
        token: String? = nil
    ) async throws -> (Data, HTTPURLResponse) {
        var req = URLRequest(url: URL(string: path, relativeTo: baseURL)!)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token {
            req.setValue(token, forHTTPHeaderField: "X-BiliCast-Token")
        }
        if let body {
            req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
            req.httpBody = body
        }
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw APIError(code: .unknown, message: "Invalid response", httpStatus: 0)
        }
        return (data, http)
    }

    private func decode<T: Decodable>(_ data: Data, http: HTTPURLResponse) throws -> T {
        let envelope = try JSONDecoder().decode(BackendEnvelope<T>.self, from: data)
        guard envelope.ok else {
            let code = envelope.error?.code ?? "UNKNOWN_ERROR"
            let message = envelope.error?.message ?? "Unknown error"
            throw APIError(code: .unknown, message: "\(code): \(message)", httpStatus: http.statusCode)
        }
        guard let value = envelope.data else {
            throw APIError(code: .unknown, message: "Empty response data", httpStatus: http.statusCode)
        }
        return value
    }

    // MARK: - Public API (mirrors Go backend endpoints)

    /// GET /api/health — no token required.
    public func health() async throws -> HealthResponse {
        let (data, http) = try await request("GET", "/api/health")
        return try decode(data, http: http)
    }

    /// GET /api/pairing/status — no token required.
    public func pairingStatus(token: String) async throws -> Bool {
        let (data, http) = try await request("GET", "/api/pairing/status", token: token)
        let envelope = try JSONDecoder().decode(BackendEnvelope<PairingStatusResponse>.self, from: data)
        return envelope.data?.paired ?? false
    }

    /// GET /api/devices — token required.
    public func devices(token: String) async throws -> [BackendDevice] {
        let (data, _) = try await request("GET", "/api/devices", token: token)
        let envelope = try JSONDecoder().decode(BackendEnvelope<DevicesResponse>.self, from: data)
        return envelope.data?.devices ?? []
    }

    /// POST /api/devices/refresh — token required.
    public func refreshDevices(token: String) async throws -> Int {
        let (data, _) = try await request("POST", "/api/devices/refresh", token: token)
        let envelope = try JSONDecoder().decode(BackendEnvelope<RefreshResponse>.self, from: data)
        return envelope.data?.count ?? 0
    }

    /// GET /api/status — token required.
    public func status(token: String) async throws -> StatusResponse {
        let (data, http) = try await request("GET", "/api/status", token: token)
        return try decode(data, http: http)
    }

    /// GET /api/preferences — token required.
    public func preferences(token: String) async throws -> PreferencesResponse {
        let (data, http) = try await request("GET", "/api/preferences", token: token)
        return try decode(data, http: http)
    }

    /// PUT /api/preferences — token required.
    public func setPreferences(_ pref: QualityPreference, token: String) async throws -> PreferencesResponse {
        let body = try JSONEncoder().encode(["qualityPreference": pref.rawValue])
        let (data, http) = try await request("PUT", "/api/preferences", body: body, token: token)
        return try decode(data, http: http)
    }

    /// POST /api/cast — token required.
    public func cast(_ req: BackendCastRequest, token: String) async throws -> BackendCastResult {
        let body = try JSONEncoder().encode(req)
        let (data, http) = try await request("POST", "/api/cast", body: body, token: token)
        return try decode(data, http: http)
    }

    /// POST /api/cast/stop — token required.
    public func stopCast(deviceId: String, token: String) async throws {
        let body = try JSONEncoder().encode(["deviceId": deviceId])
        let (data, http) = try await request("POST", "/api/cast/stop", body: body, token: token)
        _ = try decode(data, http: http) as BackendEnvelope<StopCastResponse>
    }
}

// MARK: - Response types (mirrors Go backend JSON shapes)

public struct HealthResponse: Decodable, Sendable {
    public let app: String
    public let version: String
    public let apiVersion: Int
}

public struct PairingStatusResponse: Decodable, Sendable {
    public let paired: Bool
}

public struct DevicesResponse: Decodable, Sendable {
    public let devices: [BackendDevice]
}

public struct RefreshResponse: Decodable, Sendable {
    public let count: Int
}

public struct StatusResponse: Decodable, Sendable {
    public let running: Bool
    public let currentSession: CurrentSessionInfo?
    public let qualityPreference: String
    public let qualityPreferenceOptions: [String]
    public let ffmpegAvailable: Bool
    public let controlAddr: String
    public let proxyAddr: String
    public let clients: [String]
}

public struct CurrentSessionInfo: Decodable, Sendable {
    public let sessionId: String
    public let deviceId: String
    public let title: String
    public let deviceName: String
    public let tier: String
    public let startedAt: String
}

public struct PreferencesResponse: Decodable, Sendable {
    public let qualityPreference: String
    public let qualityPreferenceOptions: [String]
    public let ffmpegAvailable: Bool
}

public struct BackendDevice: Decodable, Sendable {
    public let id: String
    public let name: String
    public let modelName: String?
    public let manufacturer: String?
    public let location: String?
    public let available: Bool
    public let avTransportControlURL: String?
    public let avTransportServiceType: String?
}

public struct BackendCastRequest: Encodable, Sendable {
    public let deviceId: String
    public let pageUrl: String
    public let bv: String?
    public let title: String
    public let currentTime: Double?
    public let source: String?
    public let candidates: [BackendCandidate]

    public init(
        deviceId: String,
        pageUrl: String,
        bv: String? = nil,
        title: String = "BiliCast",
        currentTime: Double? = nil,
        source: String? = nil,
        candidates: [BackendCandidate]
    ) {
        self.deviceId = deviceId
        self.pageUrl = pageUrl
        self.bv = bv
        self.title = title
        self.currentTime = currentTime
        self.source = source
        self.candidates = candidates
    }
}

public struct BackendCandidate: Encodable, Sendable {
    public let url: String
    public let kind: String
    public let quality: Int?
    public let mime: String?
    public let codec: String?

    public init(url: String, kind: String, quality: Int? = nil, mime: String? = nil, codec: String? = nil) {
        self.url = url
        self.kind = kind
        self.quality = quality
        self.mime = mime
        self.codec = codec
    }
}

public struct BackendCastResult: Decodable, Sendable {
    public let sessionId: String
    public let deviceName: String
    public let streamUrl: String
    public let title: String
    public let tier: String
}

public struct StopCastResponse: Decodable, Sendable {
    public let deviceId: String
}

// MARK: - Generic envelope

private struct BackendEnvelope<T: Decodable>: Decodable {
    let ok: Bool
    let data: T?
    let error: BackendAPIError?
}

private struct BackendAPIError: Decodable {
    let code: String
    let message: String
}
