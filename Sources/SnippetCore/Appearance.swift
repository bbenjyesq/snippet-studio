import Foundation

/// The 13 standard Mac colors a group can use, by name; the app turns each into the system color.
public let groupColors = ["red", "orange", "yellow", "green", "mint", "teal", "cyan", "blue", "indigo", "purple", "pink", "brown", "gray"]

public struct SnippetGroup: Codable, Equatable, Identifiable, Sendable {
    public var id = UUID()
    public var name: String
    public var color: String

    public init(name: String, color: String) {
        self.name = name
        self.color = color
    }
}

/// Snippet Studio's own groups, icons and edit dates, kept apart from Espanso's files.
/// Snippets are known by their shortcut; no snippet text is stored here.
public struct Appearance: Codable, Equatable, Sendable {
    public var groups: [SnippetGroup] = []
    public var groupOf: [String: UUID] = [:]
    public var iconOf: [String: String] = [:]
    public var editedAt: [String: Date] = [:]

    public init() {}

    // A file missing a field (say, one a later version adds) still loads; the field starts empty.
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        groups = try values.decodeIfPresent([SnippetGroup].self, forKey: .groups) ?? []
        groupOf = try values.decodeIfPresent([String: UUID].self, forKey: .groupOf) ?? [:]
        iconOf = try values.decodeIfPresent([String: String].self, forKey: .iconOf) ?? [:]
        editedAt = try values.decodeIfPresent([String: Date].self, forKey: .editedAt) ?? [:]
    }

    public func group(of snippet: Snippet) -> SnippetGroup? {
        groupOf[appearanceKey(snippet)].flatMap { id in groups.first { $0.id == id } }
    }

    public func icon(of snippet: Snippet) -> String? { iconOf[appearanceKey(snippet)] }

    /// When the app changes a shortcut, its group, icon and edit date go with it.
    public mutating func move(from old: String, to new: String) {
        guard old != new else { return }
        groupOf[new] = groupOf.removeValue(forKey: old)
        iconOf[new] = iconOf.removeValue(forKey: old)
        editedAt[new] = editedAt.removeValue(forKey: old)
    }

    public mutating func forget(_ key: String) {
        groupOf[key] = nil
        iconOf[key] = nil
        editedAt[key] = nil
    }

    /// Deleting a group only ungroups its snippets.
    public mutating func deleteGroup(_ id: UUID) {
        groups.removeAll { $0.id == id }
        groupOf = groupOf.filter { $0.value != id }
    }
}

/// shortcut: a snippet with no plain shortcut (e.g. `regex:`) is known by its position, so its color can move
/// if snippets above it are deleted; give those a stable key if they ever matter.
public func appearanceKey(_ snippet: Snippet) -> String { snippet.triggers.first ?? snippet.id }

public let appearanceFile = demoFolder?.appending(path: "appearance.json")
    ?? URL.applicationSupportDirectory.appending(path: "Snippet Studio/appearance.json")

public func loadAppearance(from url: URL = appearanceFile) -> Appearance {
    guard FileManager.default.fileExists(atPath: url.path) else { return Appearance() } // none yet
    if let data = try? Data(contentsOf: url), let appearance = try? JSONDecoder().decode(Appearance.self, from: data) {
        return appearance
    }
    // Set a file that exists but can't be read aside, rather than overwrite it on the next save. Each gets its own name.
    func aside(_ date: Date) -> URL {
        url.deletingLastPathComponent().appending(path: "appearance (unreadable \(stampFormatter.string(from: date))).json")
    }
    var date = Date.now
    while FileManager.default.fileExists(atPath: aside(date).path) { date += 0.001 } // two in one millisecond
    try? FileManager.default.moveItem(at: url, to: aside(date))
    return Appearance()
}

public func saveAppearance(_ appearance: Appearance, to url: URL = appearanceFile) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(appearance)
    // Keep the version before this save, so one bad change can be undone by hand.
    if let previous = try? Data(contentsOf: url), previous != data {
        try previous.write(to: url.deletingLastPathComponent().appending(path: "appearance (previous).json"), options: .atomic)
    }
    try data.write(to: url, options: .atomic)
}
