import Foundation
import Darwin

public enum NetworkInfo {
    /// Returns the first non-loopback IPv4 address on en* / eth* (Wi-Fi or Ethernet).
    public static func primaryIPv4() -> String? {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return nil }
        defer { freeifaddrs(head) }

        // Two passes: prefer en0 / en1; otherwise any en* / eth*.
        for namePref in ["en0", "en1", ""] {
            var ptr: UnsafeMutablePointer<ifaddrs>? = first
            while let p = ptr {
                let ifa = p.pointee
                let flags = Int32(ifa.ifa_flags)
                if (flags & IFF_UP) != 0,
                   (flags & IFF_LOOPBACK) == 0,
                   let saAddr = ifa.ifa_addr,
                   saAddr.pointee.sa_family == sa_family_t(AF_INET) {
                    let name = String(cString: ifa.ifa_name)
                    let nameMatches: Bool = {
                        if namePref.isEmpty { return name.hasPrefix("en") || name.hasPrefix("eth") }
                        return name == namePref
                    }()
                    if nameMatches {
                        var hostBuf = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                        let r = getnameinfo(
                            saAddr,
                            socklen_t(MemoryLayout<sockaddr_in>.size),
                            &hostBuf,
                            socklen_t(hostBuf.count),
                            nil,
                            0,
                            NI_NUMERICHOST
                        )
                        if r == 0 {
                            return String(cString: hostBuf)
                        }
                    }
                }
                ptr = ifa.ifa_next
            }
        }
        return nil
    }
}
