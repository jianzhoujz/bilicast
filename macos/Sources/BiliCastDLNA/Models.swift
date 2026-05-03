import Foundation

public struct DLNADevice: Sendable, Equatable {
    public let id: String                    // UDN
    public let name: String                  // friendlyName
    public let manufacturer: String?
    public let modelName: String?
    public let location: URL                 // device description URL
    public let avTransportServiceType: String   // e.g. urn:schemas-upnp-org:service:AVTransport:1
    public let avTransportControlURL: URL    // resolved absolute
    public let lastSeen: Date

    public init(
        id: String,
        name: String,
        manufacturer: String?,
        modelName: String?,
        location: URL,
        avTransportServiceType: String,
        avTransportControlURL: URL,
        lastSeen: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.manufacturer = manufacturer
        self.modelName = modelName
        self.location = location
        self.avTransportServiceType = avTransportServiceType
        self.avTransportControlURL = avTransportControlURL
        self.lastSeen = lastSeen
    }

    public func toJSON() -> [String: Any] {
        var d: [String: Any] = [
            "id": id,
            "name": name,
            "location": location.absoluteString,
            "available": true,
            "lastSeen": ISO8601DateFormatter().string(from: lastSeen),
        ]
        if let m = manufacturer { d["manufacturer"] = m }
        if let m = modelName { d["modelName"] = m }
        return d
    }
}
