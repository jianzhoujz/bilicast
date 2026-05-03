import Foundation
import os
import BiliCastCore

public final class DLNADiscovery: @unchecked Sendable {
    public static let shared = DLNADiscovery()

    public let registry = DeviceRegistry()

    private let inFlight = OSAllocatedUnfairLock<Task<Int, Never>?>(initialState: nil)

    public init() {}

    /// Performs an SSDP search and updates the registry.
    /// Concurrent calls coalesce into the same in-flight task.
    @discardableResult
    public func refresh(timeout: TimeInterval = 3.0) async -> Int {
        let task: Task<Int, Never> = inFlight.withLock { state in
            if let existing = state { return existing }
            let t = Task<Int, Never> { [registry] in
                await Self.runRefresh(into: registry, timeout: timeout)
            }
            state = t
            return t
        }
        let count = await task.value
        inFlight.withLock { state in
            if state == task { state = nil }
        }
        return count
    }

    private static func runRefresh(into registry: DeviceRegistry, timeout: TimeInterval) async -> Int {
        let started = Date()
        // Search for MediaRenderer (preferred) and AVTransport service in parallel.
        async let a = Task.detached(priority: .userInitiated) {
            SSDP.search(target: SSDP.targetMediaRenderer, mx: 2, timeout: timeout)
        }.value
        async let b = Task.detached(priority: .userInitiated) {
            SSDP.search(target: SSDP.targetAVTransport, mx: 2, timeout: timeout)
        }.value
        let responses = await a + b

        var locations = [URL]()
        var seen = Set<URL>()
        for r in responses {
            guard let u = r.location else { continue }
            if seen.insert(u).inserted { locations.append(u) }
        }
        Log.dlna.info("SSDP collected \(responses.count) responses, \(locations.count) unique LOCATIONs in \(String(format: "%.2f", Date().timeIntervalSince(started)))s")

        await withTaskGroup(of: DLNADevice?.self) { group in
            for loc in locations {
                group.addTask { await Self.fetchDevice(at: loc) }
            }
            for await device in group {
                if let d = device {
                    registry.upsert(d)
                    Log.dlna.info("device: \(d.name, privacy: .public) udn=\(d.id, privacy: .public) avTransport=\(d.avTransportControlURL.absoluteString, privacy: .public)")
                }
            }
        }
        return registry.all().count
    }

    private static func fetchDevice(at location: URL) async -> DLNADevice? {
        var req = URLRequest(url: location)
        req.timeoutInterval = 4
        req.setValue("BiliCastHelper/\(BiliCast.version) UPnP/1.1", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            let parser = XMLParser(data: data)
            let delegate = DeviceDescriptionParser()
            parser.delegate = delegate
            guard parser.parse() else { return nil }
            let parsed = delegate.result
            guard !parsed.udn.isEmpty else { return nil }
            guard let avt = parsed.services.first(where: { $0.type.contains(":service:AVTransport:") }) else {
                return nil // not a media renderer (or doesn't expose AVTransport)
            }
            guard let controlURL = URL(string: avt.controlURL, relativeTo: location)?.absoluteURL else { return nil }
            return DLNADevice(
                id: parsed.udn,
                name: parsed.friendlyName.isEmpty ? "Unknown Device" : parsed.friendlyName,
                manufacturer: parsed.manufacturer.isEmpty ? nil : parsed.manufacturer,
                modelName: parsed.modelName.isEmpty ? nil : parsed.modelName,
                location: location,
                avTransportServiceType: avt.type,
                avTransportControlURL: controlURL,
                lastSeen: Date()
            )
        } catch {
            Log.dlna.debug("fetchDevice failed \(location.absoluteString, privacy: .public): \(String(describing: error), privacy: .public)")
            return nil
        }
    }
}
