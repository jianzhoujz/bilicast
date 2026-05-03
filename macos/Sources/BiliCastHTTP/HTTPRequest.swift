import Foundation

public struct HTTPRequest: Sendable {
    public let method: String
    public let path: String
    public let query: [String: String]
    public let httpVersion: String
    public let headers: [(String, String)]
    public let body: Data

    public func header(_ name: String) -> String? {
        let lower = name.lowercased()
        return headers.first(where: { $0.0.lowercased() == lower })?.1
    }

    public func jsonBody() -> [String: Any]? {
        guard !body.isEmpty,
              let obj = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
        else { return nil }
        return obj
    }
}
