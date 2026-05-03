import Foundation

public enum APIErrorCode: String, Sendable {
    case serviceOffline = "SERVICE_OFFLINE"
    case tokenMissing = "TOKEN_MISSING"
    case tokenInvalid = "TOKEN_INVALID"
    case noDevice = "NO_DEVICE"
    case deviceOffline = "DEVICE_OFFLINE"
    case unsupportedPage = "UNSUPPORTED_PAGE"
    case unsupportedContent = "UNSUPPORTED_CONTENT"
    case noPlayableStream = "NO_PLAYABLE_STREAM"
    case upstreamFailed = "UPSTREAM_FAILED"
    case rangeNotSupported = "RANGE_NOT_SUPPORTED"
    case dlnaSetUriFailed = "DLNA_SET_URI_FAILED"
    case dlnaPlayFailed = "DLNA_PLAY_FAILED"
    case proxyFailed = "PROXY_FAILED"
    case badRequest = "BAD_REQUEST"
    case notFound = "NOT_FOUND"
    case methodNotAllowed = "METHOD_NOT_ALLOWED"
    case payloadTooLarge = "PAYLOAD_TOO_LARGE"
    case unknown = "UNKNOWN_ERROR"
}

public struct APIError: Error, Sendable {
    public let code: APIErrorCode
    public let message: String
    public let httpStatus: Int

    public init(code: APIErrorCode, message: String, httpStatus: Int = 400) {
        self.code = code
        self.message = message
        self.httpStatus = httpStatus
    }
}
