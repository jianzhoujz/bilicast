import Foundation
import Security

public enum TokenGenerator {
    public static func generate(byteCount: Int = 32) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
        if status != errSecSuccess {
            for i in 0..<byteCount { bytes[i] = UInt8.random(in: 0...255) }
        }
        return Data(bytes).base64URLEncodedString()
    }
}

public extension Data {
    func base64URLEncodedString() -> String {
        let s = base64EncodedString()
        return s.replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
    }
}

public func constantTimeEquals(_ a: String, _ b: String) -> Bool {
    let ab = Array(a.utf8), bb = Array(b.utf8)
    if ab.count != bb.count { return false }
    var diff: UInt8 = 0
    for i in 0..<ab.count { diff |= ab[i] ^ bb[i] }
    return diff == 0
}
