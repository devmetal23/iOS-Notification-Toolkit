import Foundation
import ToolkitCore

/// One ready-made shared shortcut (FR-2), loaded from `ShortcutCatalog.json`.
/// Maintainers author the shortcuts and fill the links as docs/shortcuts.md describes.
struct ShortcutCatalogEntry: Identifiable, Hashable, Sendable {
    enum Category: String, CaseIterable, Hashable, Sendable, Decodable {
        // Catalog sections appear in this order.
        case messaging
        case email
        case work
        case social
        case shoppingAndRides
        case finance
        /// The base shortcut's own category. Never listed as a catalog section.
        case toolkit

        var title: LocalizedStringResource {
            switch self {
            case .messaging: "Calls & Messages"
            case .email: "Email"
            case .work: "Work"
            case .social: "Social"
            case .shoppingAndRides: "Shopping, Food & Rides"
            case .finance: "Money"
            case .toolkit: "Notification Toolkit"
            }
        }
    }

    /// Stable slug. Never reused for a different app: it is stored as `TrackedApp.catalogID`.
    let id: String
    /// Plain text, exactly what the shortcut's Log Notification action passes as App.
    let displayName: String
    let category: Category
    let shortcutURL: URL
    /// A generic SF Symbol. Never another app's logo or anything that imitates one.
    let symbol: String
    /// Extra words search should match, such as a former name. Never displayed.
    var keywords: [String] = []
    /// The base shortcut: its automation logs Notification Toolkit's own test
    /// notification. Offered in Test Capture and never takes a free-tier slot.
    var isBaseShortcut = false
    /// The trigger can't name one app (the generic Banking entry), so the user
    /// picks theirs while switching the automation on.
    var requiresAppSelection = false

    var appKey: AppKey { AppKey(appName: displayName) }

    /// False while the link is still a `https://www.icloud.com/shortcuts/REPLACE-<id>` placeholder.
    var isPublished: Bool { !shortcutURL.absoluteString.contains("/REPLACE-") }

    func matches(_ query: String) -> Bool {
        displayName.localizedStandardContains(query)
            || keywords.contains { $0.localizedStandardContains(query) }
            || String(localized: category.title).localizedStandardContains(query)
    }
}

extension ShortcutCatalogEntry: Decodable {
    private enum CodingKeys: String, CodingKey {
        case id, displayName, category, shortcutURL, symbol, keywords, isBaseShortcut, requiresAppSelection
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        displayName = try container.decode(String.self, forKey: .displayName)
        category = try container.decode(Category.self, forKey: .category)
        shortcutURL = try container.decode(URL.self, forKey: .shortcutURL)
        symbol = try container.decode(String.self, forKey: .symbol)
        keywords = try container.decodeIfPresent([String].self, forKey: .keywords) ?? []
        isBaseShortcut = try container.decodeIfPresent(Bool.self, forKey: .isBaseShortcut) ?? false
        requiresAppSelection = try container.decodeIfPresent(Bool.self, forKey: .requiresAppSelection) ?? false
    }
}

/// The bundled catalog: popular apps grouped by category, plus the base shortcut.
struct ShortcutCatalog: Sendable {
    struct CategoryGroup: Identifiable, Sendable {
        let category: ShortcutCatalogEntry.Category
        /// In catalog file order, which maintainers keep roughly by popularity.
        let entries: [ShortcutCatalogEntry]

        var id: ShortcutCatalogEntry.Category { category }
    }

    let entries: [ShortcutCatalogEntry]

    init(entries: [ShortcutCatalogEntry]) {
        self.entries = entries
    }

    init(data: Data) throws {
        struct File: Decodable {
            var schemaVersion: Int
            var entries: [ShortcutCatalogEntry]
        }
        self.init(entries: try JSONDecoder().decode(File.self, from: data).entries)
    }

    /// `ShortcutCatalog.json` from the app bundle. Empty, with an assertion in
    /// debug builds, if the file is missing or malformed.
    static let bundled: ShortcutCatalog = {
        guard let url = Bundle.main.url(forResource: "ShortcutCatalog", withExtension: "json") else {
            assertionFailure("ShortcutCatalog.json is missing from the app bundle")
            return ShortcutCatalog(entries: [])
        }
        do {
            let catalog = try ShortcutCatalog(data: Data(contentsOf: url))
            assert(
                catalog.baseShortcut?.appKey == .ownApp,
                "ShortcutCatalog.json needs one base shortcut whose displayName is Notification Toolkit"
            )
            return catalog
        } catch {
            assertionFailure("ShortcutCatalog.json can't be read: \(error)")
            return ShortcutCatalog(entries: [])
        }
    }()

    var baseShortcut: ShortcutCatalogEntry? {
        entries.first { $0.isBaseShortcut }
    }

    /// Every entry except the base shortcut.
    var apps: [ShortcutCatalogEntry] {
        entries.filter { !$0.isBaseShortcut }
    }

    /// Apps matching `query` (all of them when it's blank), grouped by category.
    func groups(matching query: String) -> [CategoryGroup] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let matching = apps.filter { query.isEmpty || $0.matches(query) }
        return ShortcutCatalogEntry.Category.allCases.compactMap { category in
            guard category != .toolkit else { return nil }
            let entries = matching.filter { $0.category == category }
            return entries.isEmpty ? nil : CategoryGroup(category: category, entries: entries)
        }
    }
}
