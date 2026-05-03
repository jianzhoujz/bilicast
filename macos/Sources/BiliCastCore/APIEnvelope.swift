import Foundation

public enum APIEnvelope {
    public static func success(_ data: Any = NSNull()) -> Data {
        let obj: [String: Any] = ["ok": true, "data": data, "error": NSNull()]
        return serialize(obj, fallback: #"{"ok":true,"data":null,"error":null}"#)
    }

    public static func failure(_ error: APIError) -> Data {
        let obj: [String: Any] = [
            "ok": false,
            "data": NSNull(),
            "error": ["code": error.code.rawValue, "message": error.message],
        ]
        return serialize(obj, fallback: #"{"ok":false,"data":null,"error":{"code":"UNKNOWN_ERROR","message":"serialize failed"}}"#)
    }

    private static func serialize(_ obj: Any, fallback: String) -> Data {
        do {
            return try JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys])
        } catch {
            return Data(fallback.utf8)
        }
    }
}
