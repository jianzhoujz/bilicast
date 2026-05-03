import Foundation

struct ParsedRequestHead {
    let method: String
    let path: String
    let query: [String: String]
    let httpVersion: String
    let headers: [(String, String)]
}

enum HTTPParser {
    static func parseHead(_ data: Data) -> ParsedRequestHead? {
        guard let s = String(data: data, encoding: .utf8) else { return nil }
        let lines = s.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let parts = requestLine
            .split(separator: " ", maxSplits: 2, omittingEmptySubsequences: false)
            .map(String.init)
        guard parts.count == 3 else { return nil }
        let method = parts[0].uppercased()
        let target = parts[1]
        let httpVersion = parts[2]

        var path = target
        var query: [String: String] = [:]
        if let q = target.firstIndex(of: "?") {
            path = String(target[..<q])
            let qs = target[target.index(after: q)...]
            for kv in qs.split(separator: "&") {
                let pair = kv.split(separator: "=", maxSplits: 1).map(String.init)
                let k = pair[0].removingPercentEncoding ?? pair[0]
                let v = pair.count > 1 ? (pair[1].removingPercentEncoding ?? pair[1]) : ""
                query[k] = v
            }
        }

        var headers: [(String, String)] = []
        for line in lines.dropFirst() {
            if line.isEmpty { continue }
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            if !name.isEmpty {
                headers.append((name, value))
            }
        }
        return ParsedRequestHead(
            method: method, path: path, query: query, httpVersion: httpVersion, headers: headers
        )
    }
}
