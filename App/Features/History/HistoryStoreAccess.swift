import Foundation
import ToolkitCore
import UIKit
import UniformTypeIdentifiers

/// Runs store work off the main actor. The store is `Sendable` and every call is a
/// short synchronous transaction, so search and paging never block scrolling.
enum HistoryStoreAccess {
    @concurrent
    static func perform<Value: Sendable>(
        on store: any NotificationStoring,
        _ work: @Sendable (any NotificationStoring) throws -> Value
    ) async throws -> Value {
        try work(store)
    }
}

/// Deletes history from the app (FR-13). Every deletion cancels the snoozes it
/// removed and tells the rest of the app that history changed.
@MainActor
enum HistoryDeletion {
    static func deleteEntry(_ id: NotificationEntry.ID, model: AppModel) async throws {
        try await run(model) { try $0.deleteEntry(id: id) }
    }

    /// Returns how many entries were deleted.
    @discardableResult
    static func deleteEntries(from app: AppKey, model: AppModel) async throws -> Int {
        try await run(model) { try $0.deleteEntries(app: app) }.entriesDeleted
    }

    /// Returns how many entries were deleted.
    @discardableResult
    static func deleteAll(model: AppModel) async throws -> Int {
        try await run(model) { try $0.deleteAll() }.entriesDeleted
    }

    @discardableResult
    private static func run(
        _ model: AppModel,
        _ work: @Sendable (any NotificationStoring) throws -> DeletionResult
    ) async throws -> DeletionResult {
        let store = try model.store()
        let result = try await HistoryStoreAccess.perform(on: store, work)
        model.snoozes.cancel(requestIdentifiers: result.cancelledSnoozeRequestIdentifiers)
        model.historyDidChange()
        return result
    }
}

/// Copies notification text. Local only, so codes and messages don't sync to the
/// user's other devices through Universal Clipboard.
@MainActor
enum HistoryPasteboard {
    static func copy(_ text: String) {
        UIPasteboard.general.setItems(
            [[UTType.utf8PlainText.identifier: text]],
            options: [.localOnly: true]
        )
    }
}

/// Why history couldn't be read.
enum HistoryLoadFailure: Hashable, Sendable {
    /// The database is protected until the first unlock after a restart (NFR-2).
    case protectedDataUnavailable
    case other

    init(_ error: any Error) {
        self = (error as? StoreError) == .unavailable ? .protectedDataUnavailable : .other
    }
}

enum HistoryErrorText {
    /// A short explanation for an alert after a failed delete or load.
    static func message(for error: any Error) -> String {
        switch HistoryLoadFailure(error) {
        case .protectedDataUnavailable:
            String(localized: "Unlock your iPhone, then try again.")
        case .other:
            String(localized: "Something went wrong. Please try again.")
        }
    }
}

extension NotificationEntry {
    /// Title, subtitle and message on separate lines, for copying.
    var historyFullText: String {
        [title, subtitle, body].filter { !$0.isEmpty }.joined(separator: "\n")
    }
}
