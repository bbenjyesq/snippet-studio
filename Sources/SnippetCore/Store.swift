import Foundation

/// Backups live outside Espanso's folder so Espanso never loads them as snippets.
public let backupFolder = demoFolder?.appending(path: "Backups")
    ?? URL.applicationSupportDirectory.appending(path: "Snippet Studio/Backups")

public struct Backup: Identifiable, Sendable {
    public let url: URL
    public let file: String
    public let date: Date
    public var id: URL { url }
}

/// Saves one change: backs up the file, then writes the new text in a single atomic step.
/// `shown` is the snippet as the person saw it; if the file has changed since, nothing is saved.
public func save(_ change: Change, file: String, shown: Snippet? = nil,
                 matchFolder: URL = espansoMatchFolder, backups: URL = backupFolder) throws {
    guard !file.contains("/") else { throw EditError.packageFile }
    // Resolve symlinks so the atomic write updates the real file instead of replacing the link.
    let url = matchFolder.appending(path: "\(file).yml").resolvingSymlinksInPath()
    let original = try String(contentsOf: url, encoding: .utf8)
    if let shown {
        let current = try parseMatches(yaml: original, file: file)
        guard current.indices.contains(shown.index), Content(current[shown.index]) == Content(shown)
        else { throw EditError.fileChangedElsewhere }
    }
    let updated = try applying(change, to: original, file: file)
    try backUp(original, file: file, to: backups)
    try updated.write(to: url, atomically: true, encoding: .utf8)
}

public func listBackups(in backups: URL = backupFolder) -> [Backup] {
    let urls = (try? FileManager.default.contentsOfDirectory(at: backups, includingPropertiesForKeys: nil)) ?? []
    return urls.compactMap { url in
        let parts = url.deletingPathExtension().lastPathComponent.components(separatedBy: " @ ")
        guard parts.count == 2, let date = stampFormatter.date(from: parts[1]) else { return nil }
        return Backup(url: url, file: parts[0], date: date)
    }
    .sorted { $0.date > $1.date }
}

/// Puts a backup back in place. The current file is backed up first, so a restore can itself be undone.
public func restore(_ backup: Backup, matchFolder: URL = espansoMatchFolder, backups: URL = backupFolder) throws {
    let saved = try String(contentsOf: backup.url, encoding: .utf8)
    _ = try parseMatches(yaml: saved, file: backup.file) // never restore a file Espanso couldn't read
    let url = matchFolder.appending(path: "\(backup.file).yml").resolvingSymlinksInPath()
    if let current = try? String(contentsOf: url, encoding: .utf8) {
        try backUp(current, file: backup.file, to: backups)
    }
    try saved.write(to: url, atomically: true, encoding: .utf8)
}

/// How many backups are kept; older ones are deleted after each new one.
let backupsKept = 200

func backUp(_ text: String, file: String, to backups: URL) throws {
    try FileManager.default.createDirectory(at: backups, withIntermediateDirectories: true)
    func url(_ date: Date) -> URL { backups.appending(path: "\(file) @ \(stampFormatter.string(from: date)).yml") }
    var date = Date.now
    while FileManager.default.fileExists(atPath: url(date).path) { date += 0.001 } // two saves in one millisecond
    try Data(text.utf8).write(to: url(date), options: .withoutOverwriting)
    for old in listBackups(in: backups).dropFirst(backupsKept) { try? FileManager.default.removeItem(at: old.url) }
}

let stampFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = .gmt // local time repeats an hour when clocks go back; the list still shows local time
    formatter.dateFormat = "yyyy-MM-dd HH.mm.ss.SSS"
    return formatter
}()
