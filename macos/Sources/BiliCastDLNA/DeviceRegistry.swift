import Foundation

public final class DeviceRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var byID: [String: DLNADevice] = [:]

    public init() {}

    public func upsert(_ d: DLNADevice) {
        lock.lock(); defer { lock.unlock() }
        byID[d.id] = d
    }

    public func get(id: String) -> DLNADevice? {
        lock.lock(); defer { lock.unlock() }
        return byID[id]
    }

    public func all() -> [DLNADevice] {
        lock.lock(); defer { lock.unlock() }
        return byID.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public func clear() {
        lock.lock(); defer { lock.unlock() }
        byID.removeAll()
    }
}
