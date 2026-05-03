import Foundation
import BiliCastCore

public struct HTTPResponse: Sendable {
    public var status: Int
    public var reason: String
    public var headers: [(String, String)]
    public var body: Data

    public init(status: Int, reason: String, headers: [(String, String)] = [], body: Data = Data()) {
        self.status = status
        self.reason = reason
        self.headers = headers
        self.body = body
    }

    public static func json(status: Int = 200, body: Data) -> HTTPResponse {
        HTTPResponse(
            status: status,
            reason: reasonPhrase(for: status),
            headers: [
                ("Content-Type", "application/json; charset=utf-8"),
                ("Cache-Control", "no-store"),
            ],
            body: body
        )
    }

    public static func ok(_ data: Any = NSNull()) -> HTTPResponse {
        json(status: 200, body: APIEnvelope.success(data))
    }

    public static func error(_ err: APIError) -> HTTPResponse {
        json(status: err.httpStatus, body: APIEnvelope.failure(err))
    }

    public static func reasonPhrase(for status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 204: return "No Content"
        case 206: return "Partial Content"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 403: return "Forbidden"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 413: return "Payload Too Large"
        case 416: return "Range Not Satisfiable"
        case 431: return "Request Header Fields Too Large"
        case 500: return "Internal Server Error"
        default:  return "OK"
        }
    }
}
