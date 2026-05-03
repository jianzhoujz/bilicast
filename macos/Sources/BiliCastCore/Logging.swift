import Foundation
import os

public enum Log {
    private static let subsystem = "local.bilicast"
    public static let app  = Logger(subsystem: subsystem, category: "app")
    public static let http = Logger(subsystem: subsystem, category: "http")
    public static let dlna = Logger(subsystem: subsystem, category: "dlna")

    public static func redact(_ s: String, keep: Int = 6) -> String {
        if s.isEmpty { return "(empty)" }
        guard s.count > keep else { return String(repeating: "*", count: s.count) }
        return "\(s.prefix(keep))…(\(s.count)c)"
    }
}
