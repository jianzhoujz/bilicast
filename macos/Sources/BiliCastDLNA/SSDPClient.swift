import Foundation
import Darwin
import BiliCastCore

public struct SSDPResponse: Sendable {
    public let headers: [String: String]
    public let sourceIP: String

    public var location: URL? { headers["LOCATION"].flatMap { URL(string: $0) } }
    public var usn: String?   { headers["USN"] }
    public var st: String?    { headers["ST"] }
    public var server: String? { headers["SERVER"] }
}

public enum SSDP {
    public static let multicastAddress = "239.255.255.250"
    public static let multicastPort: in_port_t = 1900

    public static let targetMediaRenderer = "urn:schemas-upnp-org:device:MediaRenderer:1"
    public static let targetAVTransport   = "urn:schemas-upnp-org:service:AVTransport:1"
    public static let targetAll           = "ssdp:all"

    /// Sends an M-SEARCH and collects responses for `timeout` seconds.
    /// Synchronous; runs in the calling thread (caller should use Task.detached).
    public static func search(
        target: String = targetMediaRenderer,
        mx: Int = 2,
        timeout: TimeInterval = 3.0
    ) -> [SSDPResponse] {
        let fd = socket(AF_INET, SOCK_DGRAM, 0)
        guard fd >= 0 else {
            Log.dlna.error("SSDP socket() failed errno=\(errno)")
            return []
        }
        defer { close(fd) }

        var ttl: UInt8 = 4
        _ = setsockopt(fd, IPPROTO_IP, IP_MULTICAST_TTL, &ttl, socklen_t(MemoryLayout<UInt8>.size))
        var loop: UInt8 = 0
        _ = setsockopt(fd, IPPROTO_IP, IP_MULTICAST_LOOP, &loop, socklen_t(MemoryLayout<UInt8>.size))
        var reuse: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var bindAddr = sockaddr_in()
        memset(&bindAddr, 0, MemoryLayout<sockaddr_in>.size)
        bindAddr.sin_family = sa_family_t(AF_INET)
        bindAddr.sin_addr.s_addr = INADDR_ANY.bigEndian
        bindAddr.sin_port = 0
        let bres = withUnsafePointer(to: &bindAddr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if bres != 0 {
            Log.dlna.error("SSDP bind failed errno=\(errno)")
            return []
        }

        let payload =
            "M-SEARCH * HTTP/1.1\r\n" +
            "HOST: \(multicastAddress):\(multicastPort)\r\n" +
            "MAN: \"ssdp:discover\"\r\n" +
            "MX: \(mx)\r\n" +
            "ST: \(target)\r\n" +
            "USER-AGENT: macOS/\(ProcessInfo.processInfo.operatingSystemVersionString) UPnP/1.1 BiliCast/\(BiliCast.version)\r\n" +
            "\r\n"

        var dst = sockaddr_in()
        memset(&dst, 0, MemoryLayout<sockaddr_in>.size)
        dst.sin_family = sa_family_t(AF_INET)
        dst.sin_port = multicastPort.bigEndian
        dst.sin_addr.s_addr = inet_addr(multicastAddress)

        let bytes = Array(payload.utf8)
        // Send the M-SEARCH twice, ~150ms apart, to improve hit rate (some devices drop the first).
        for i in 0..<2 {
            let sent = bytes.withUnsafeBufferPointer { buf -> Int in
                withUnsafePointer(to: &dst) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                        sendto(fd, buf.baseAddress, buf.count, 0, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
            }
            if sent < 0 {
                Log.dlna.error("SSDP sendto failed errno=\(errno)")
                return []
            }
            if i == 0 { usleep(150_000) }
        }

        // Per-recv timeout = 200ms; keep collecting until overall timeout elapses.
        var tv = timeval(tv_sec: 0, tv_usec: 200_000)
        _ = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        let deadline = Date().addingTimeInterval(timeout)
        var buffer = [UInt8](repeating: 0, count: 8192)
        var responses: [SSDPResponse] = []
        while Date() < deadline {
            var src = sockaddr_in()
            memset(&src, 0, MemoryLayout<sockaddr_in>.size)
            var srcLen = socklen_t(MemoryLayout<sockaddr_in>.size)
            let n: Int = buffer.withUnsafeMutableBufferPointer { buf in
                withUnsafeMutablePointer(to: &src) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                        recvfrom(fd, buf.baseAddress, buf.count, 0, sa, &srcLen)
                    }
                }
            }
            if n <= 0 { continue }
            let data = Data(buffer.prefix(n))
            guard let s = String(data: data, encoding: .utf8) else { continue }
            guard let parsed = parse(s, sourceAddr: src) else { continue }
            responses.append(parsed)
        }
        return responses
    }

    private static func parse(_ s: String, sourceAddr: sockaddr_in) -> SSDPResponse? {
        let lines = s.components(separatedBy: "\r\n")
        guard let first = lines.first else { return nil }
        // SSDP responses start with HTTP/1.1 200 OK; NOTIFY messages start with NOTIFY * HTTP/1.1.
        let upper = first.uppercased()
        guard upper.hasPrefix("HTTP/1.1 200") || upper.hasPrefix("HTTP/1.0 200") else { return nil }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            if line.isEmpty { continue }
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].uppercased().trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            headers[name] = value
        }
        var src = sourceAddr
        var ipBuf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        let ip = inet_ntop(AF_INET, &src.sin_addr, &ipBuf, socklen_t(INET_ADDRSTRLEN)).map { String(cString: $0) } ?? "?"
        return SSDPResponse(headers: headers, sourceIP: ip)
    }
}
