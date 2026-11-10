import os

/// 界面线程和音频线程之间传值的小盒子。
/// 音频线程只用 `tryWithLock`（拿不到锁就跳过这一轮），永远不会被阻塞。
public final class LockedValue<Value: Sendable>: @unchecked Sendable {
    private let lock: OSAllocatedUnfairLock<Value>

    public init(_ value: Value) {
        lock = OSAllocatedUnfairLock(initialState: value)
    }

    public func withLock<R>(_ body: (inout Value) -> R) -> R {
        lock.withLockUnchecked(body)
    }

    public func tryWithLock<R>(_ body: (inout Value) -> R) -> R? {
        lock.withLockIfAvailableUnchecked(body)
    }

    public var value: Value { lock.withLockUnchecked { $0 } }
}
