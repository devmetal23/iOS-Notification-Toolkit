import Darwin
import Foundation
import Synchronization
import ToolkitCore
import UIKit

/// The parameters of one Log Spike Notification run, exactly as Shortcuts passed them.
struct SpikeCaptureInput: Sendable {
    var app: String?
    var title: String?
    var subtitle: String?
    var body: String?
    var date: Date?
    var isTimeSensitive: Bool?
    var raw: String?

    func newNotification(capturedAt: Date) -> NewNotification {
        NewNotification(
            appName: app.flatMap { $0.isEmpty ? nil : $0 } ?? "(no app)",
            title: title ?? "",
            subtitle: subtitle ?? "",
            body: body ?? "",
            receivedAt: date ?? capturedAt,
            isTimeSensitive: isTimeSensitive ?? false
        )
    }
}

/// Records one capture: device state, then the SQLite insert, then the JSON line.
/// Each write has its own `do`/`catch`, so a failure in one never skips the other.
enum SpikeRecorder {
    private static let capturesInProcess = Atomic<Int>(0)

    @concurrent
    @discardableResult
    static func record(_ input: SpikeCaptureInput, startedAt start: ContinuousClock.Instant, capturedAt: Date) async -> SpikeEvent {
        let captureIndex = capturesInProcess.wrappingAdd(1, ordering: .relaxed).newValue
        let launchedAt = ProcessLaunch.date

        let mainActorStart = ContinuousClock.now
        let device = await DeviceSnapshot.current()
        let mainActorTime = ContinuousClock.now - mainActorStart

        var event = SpikeEvent(
            id: UUID(),
            capturedAt: capturedAt,
            app: input.app,
            title: input.title,
            subtitle: input.subtitle,
            body: input.body,
            date: input.date,
            isTimeSensitive: input.isTimeSensitive,
            raw: input.raw,
            protectedDataAvailable: device.protectedDataAvailable,
            applicationState: device.applicationState,
            processID: getpid(),
            processLaunchedAt: launchedAt,
            secondsSinceProcessLaunch: capturedAt.timeIntervalSince(launchedAt),
            captureIndexInProcess: captureIndex,
            durationMs: 0,
            mainActorMs: mainActorTime.milliseconds,
            sqliteMs: 0,
            sqliteSucceeded: false,
            sqliteEntryID: nil,
            sqliteError: nil
        )

        // 1. The production store, with dedupe off so every run is visible.
        let sqliteStart = ContinuousClock.now
        do {
            let outcome = try SpikeStore.withStore { store in
                try store.insert(input.newNotification(capturedAt: capturedAt), capturedAt: capturedAt, dedupeWindow: 0)
            }
            switch outcome {
            case .inserted(let entry):
                event.sqliteSucceeded = true
                event.sqliteEntryID = entry.id
            case .duplicate(of: let existingID):
                // Should not happen with a zero window; recorded so it can't hide.
                event.sqliteSucceeded = true
                event.sqliteEntryID = existingID
                event.sqliteError = "duplicate of \(existingID)"
            }
        } catch {
            event.sqliteError = String(describing: error)
        }
        let finished = ContinuousClock.now
        event.sqliteMs = (finished - sqliteStart).milliseconds
        event.durationMs = (finished - start).milliseconds

        // 2. The JSON line. Runs whatever happened above.
        do {
            try SpikeEventLog.append(event)
        } catch {
            SpikeDiagnostics.recordEventLogFailure(error)
        }
        return event
    }
}

/// UIKit state that must be read on the main actor.
struct DeviceSnapshot: Sendable {
    var protectedDataAvailable: Bool
    var applicationState: String

    @MainActor
    static func current() -> DeviceSnapshot {
        let application = UIApplication.shared
        let state: String
        switch application.applicationState {
        case .active: state = "active"
        case .inactive: state = "inactive"
        case .background: state = "background"
        @unknown default: state = "unknown"
        }
        return DeviceSnapshot(protectedDataAvailable: application.isProtectedDataAvailable, applicationState: state)
    }
}

/// When this process started, from the kernel, so the time is right even when the
/// system launched NT Spike in the background just to run the intent.
enum ProcessLaunch {
    static let date: Date = kernelStartDate() ?? Date()

    private static func kernelStartDate() -> Date? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0, size > 0 else { return nil }
        let start = info.kp_proc.p_un.__p_starttime
        guard start.tv_sec > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(start.tv_sec) + TimeInterval(start.tv_usec) / 1_000_000)
    }
}

extension Duration {
    var milliseconds: Double {
        let parts = components
        return Double(parts.seconds) * 1_000 + Double(parts.attoseconds) / 1_000_000_000_000_000
    }
}
