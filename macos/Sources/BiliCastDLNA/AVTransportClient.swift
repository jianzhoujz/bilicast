import Foundation
import BiliCastCore

public final class AVTransportClient: Sendable {
    public struct SOAPError: Error, CustomStringConvertible, Sendable {
        public let action: String
        public let httpStatus: Int
        public let detail: String
        public var description: String {
            "SOAP \(action) failed (HTTP \(httpStatus)): \(detail)"
        }
    }

    private let device: DLNADevice
    private let session: URLSession

    public init(device: DLNADevice, session: URLSession = .shared) {
        self.device = device
        self.session = session
    }

    public func setURI(_ url: URL, metadata: String = "") async throws {
        let body =
            soapEnvelopeOpen() +
            "<u:SetAVTransportURI xmlns:u=\"\(device.avTransportServiceType)\">" +
            "<InstanceID>0</InstanceID>" +
            "<CurrentURI>\(xmlEscape(url.absoluteString))</CurrentURI>" +
            "<CurrentURIMetaData>\(xmlEscape(metadata))</CurrentURIMetaData>" +
            "</u:SetAVTransportURI>" +
            soapEnvelopeClose()
        try await invoke(action: "SetAVTransportURI", body: body)
    }

    public func play(speed: String = "1") async throws {
        let body =
            soapEnvelopeOpen() +
            "<u:Play xmlns:u=\"\(device.avTransportServiceType)\">" +
            "<InstanceID>0</InstanceID>" +
            "<Speed>\(xmlEscape(speed))</Speed>" +
            "</u:Play>" +
            soapEnvelopeClose()
        try await invoke(action: "Play", body: body)
    }

    public func stop() async throws {
        let body =
            soapEnvelopeOpen() +
            "<u:Stop xmlns:u=\"\(device.avTransportServiceType)\">" +
            "<InstanceID>0</InstanceID>" +
            "</u:Stop>" +
            soapEnvelopeClose()
        try await invoke(action: "Stop", body: body)
    }

    /// Convenience: stop (best-effort) → SetAVTransportURI → Play.
    public func playFromURL(_ url: URL) async throws {
        try? await stop()
        try await setURI(url)
        try await play()
    }

    private func invoke(action: String, body: String) async throws {
        var req = URLRequest(url: device.avTransportControlURL)
        req.httpMethod = "POST"
        req.timeoutInterval = 6
        req.setValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "Content-Type")
        req.setValue("\"\(device.avTransportServiceType)#\(action)\"", forHTTPHeaderField: "SOAPACTION")
        req.setValue("BiliCastHelper/\(BiliCast.version) UPnP/1.1", forHTTPHeaderField: "User-Agent")
        req.httpBody = Data(body.utf8)

        let (data, response) = try await session.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status != 200 {
            let detail = String(data: data, encoding: .utf8) ?? "(no body)"
            let truncated = String(detail.prefix(500))
            Log.dlna.error("SOAP \(action, privacy: .public) -> HTTP \(status) device=\(self.device.name, privacy: .public) detail=\(truncated, privacy: .public)")
            throw SOAPError(action: action, httpStatus: status, detail: truncated)
        }
        Log.dlna.info("SOAP \(action, privacy: .public) ok device=\(self.device.name, privacy: .public)")
    }

    private func soapEnvelopeOpen() -> String {
        #"<?xml version="1.0" encoding="utf-8"?><s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"><s:Body>"#
    }

    private func soapEnvelopeClose() -> String {
        "</s:Body></s:Envelope>"
    }
}

private func xmlEscape(_ s: String) -> String {
    var out = ""
    out.reserveCapacity(s.count)
    for c in s {
        switch c {
        case "&":  out += "&amp;"
        case "<":  out += "&lt;"
        case ">":  out += "&gt;"
        case "\"": out += "&quot;"
        case "'":  out += "&apos;"
        default:   out.append(c)
        }
    }
    return out
}
