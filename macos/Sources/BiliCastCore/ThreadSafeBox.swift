import Foundation

public final class ThreadSafeBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: T

    public init(_ initial: T) { self.value = initial }

    public func get() -> T {
        lock.lock(); defer { lock.unlock() }
        return value
    }

    public func set(_ new: T) {
        lock.lock(); defer { lock.unlock() }
        value = new
    }
}
