import Foundation
import Synchronization

/// Tells every process in the App Group that stored history changed, so an open
/// History screen reloads after Log Notification stores an entry or cleanup runs.
///
/// Uses a Darwin notification, which carries no payload: observers reload from the
/// store. Delivery is best effort and coalesced, so the app also reloads when it
/// becomes active.
enum HistoryChangeNotifier {
    /// Derived from the App Group identifier, so builds with different bundle ID
    /// prefixes on one device don't hear each other.
    static let notificationName = "\(AppGroup.identifier).historyDidChange"

    /// Posts the change to all processes, including this one.
    static func post() {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(notificationName as CFString),
            nil,
            nil,
            true
        )
    }

    /// A stream that yields once per change (bursts are coalesced). Iterate it in a
    /// view's `.task`, which runs on the main actor; the stream finishes when that
    /// task is cancelled.
    static func changes() -> AsyncStream<Void> {
        let (stream, continuation) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
        HistoryChangeObserver.shared.add(continuation)
        return stream
    }
}

/// The single process-wide Darwin observer. It is registered once and never removed,
/// so the C callback can never see a deallocated observer; streams come and go
/// through `continuations`.
private final class HistoryChangeObserver: Sendable {
    static let shared = HistoryChangeObserver(name: HistoryChangeNotifier.notificationName)

    private let continuations = Mutex<[UUID: AsyncStream<Void>.Continuation]>([:])

    private init(name: String) {
        // A C function pointer can't capture context; the observer pointer passed at
        // registration comes back as `observer`. This closure is formed in a
        // nonisolated initializer, so it carries no actor isolation and is safe to
        // call from whichever thread CoreFoundation delivers on.
        let callback: CFNotificationCallback = { _, observer, _, _, _ in
            guard let observer else { return }
            Unmanaged<HistoryChangeObserver>.fromOpaque(observer).takeUnretainedValue().broadcast()
        }
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            callback,
            name as CFString,
            nil,
            .deliverImmediately
        )
    }

    func add(_ continuation: AsyncStream<Void>.Continuation) {
        let id = UUID()
        continuations.withLock { $0[id] = continuation }
        continuation.onTermination = { [self] _ in
            continuations.withLock { _ = $0.removeValue(forKey: id) }
        }
    }

    private func broadcast() {
        let current = continuations.withLock { Array($0.values) }
        for continuation in current {
            continuation.yield()
        }
    }
}
