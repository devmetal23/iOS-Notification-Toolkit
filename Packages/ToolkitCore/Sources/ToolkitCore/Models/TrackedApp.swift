import Foundation

/// An app the user has set up: added from the catalog, or seen in a capture.
/// Drives the health check (FR-4) and the free tier's 3-app limit.
public struct TrackedApp: Identifiable, Hashable, Sendable {
    public var id: AppKey { key }

    public var key: AppKey
    public var displayName: String
    /// When the user tapped Add in the catalog, or the first capture if added by hand.
    public var addedAt: Date
    /// Catalog entry this came from (FR-2), nil for apps added through the guided flow (FR-3).
    public var catalogID: String?
    public var firstLoggedAt: Date?
    public var lastLoggedAt: Date?
    /// Entries currently stored for this app.
    public var entryCount: Int
    /// Captures dropped because the free tier's app limit was reached.
    public var blockedCount: Int

    public init(
        key: AppKey,
        displayName: String,
        addedAt: Date,
        catalogID: String? = nil,
        firstLoggedAt: Date? = nil,
        lastLoggedAt: Date? = nil,
        entryCount: Int = 0,
        blockedCount: Int = 0
    ) {
        self.key = key
        self.displayName = displayName
        self.addedAt = addedAt
        self.catalogID = catalogID
        self.firstLoggedAt = firstLoggedAt
        self.lastLoggedAt = lastLoggedAt
        self.entryCount = entryCount
        self.blockedCount = blockedCount
    }
}
