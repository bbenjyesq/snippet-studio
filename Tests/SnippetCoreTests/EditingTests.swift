import Foundation
import Testing
@testable import SnippetCore

// Invented sample only — never real snippets (see docs/PLAN.md, Security rules).
let commented = """
# Firm snippets — keep this header
matches:
  # --- Signatures ---
  - trigger: ";sig"
    replace: "Sample Law Corporation"   # inline note

  # --- Discovery ---
  - trigger: ";mcl"
    label: "Meet and confer"
    replace: |
      Dear {{form1.counsel}}:
      # this line is letter text, not a comment
    vars:
      - name: form1
        type: form
        params:
          layout: "Counsel [[counsel]]"
  - trigger: ";ip"
    replace: "{{out}}"
    vars:
      - name: out
        type: shell
        params:
          cmd: "echo hi"
# trailing comment at end of file

"""

func lines(_ s: String) -> [String] { s.components(separatedBy: "\n") }

@Test func updateRewritesOnlyThatSnippet() throws {
    let after = try applying(.update(index: 0, Draft(trigger: ";sig2", label: "Signature", text: "New text")),
                             to: commented, file: "base")
    let (old, new) = (lines(commented), lines(after))
    // Everything from the blank line after the first snippet onward is untouched, comments included.
    #expect(Array(new.suffix(from: new.firstIndex(of: "")!)) == Array(old.suffix(from: old.firstIndex(of: "")!)))
    #expect(Array(new.prefix(3)) == Array(old.prefix(3)))
    let s = try parseMatches(yaml: after, file: "base")
    #expect(s[0].triggers == [";sig2"])
    #expect(s[0].label == "Signature")
    #expect(s[0].text == "New text")
}

@Test func updateKeepsFormVariablesAndMultilineText() throws {
    let text = "Dear {{form1.counsel}}:\n§ 2016.040 “quoted”\n# still text"
    var draft = Draft(try parseMatches(yaml: commented, file: "base")[1])
    draft.text = text
    let after = try applying(.update(index: 1, draft), to: commented, file: "base")
    let s = try parseMatches(yaml: after, file: "base")[1]
    #expect(s.text == text)
    #expect(s.variables["form1"] == "form")
    #expect(s.questions.map(\.name) == ["counsel"])
    #expect(after.contains("§ 2016.040 “quoted”")) // written as readable text, not escape codes
    #expect(after.hasSuffix("# trailing comment at end of file\n"))
}

@Test func emptyLabelIsRemoved() throws {
    var draft = Draft(try parseMatches(yaml: commented, file: "base")[1])
    draft.label = ""
    let after = try applying(.update(index: 1, draft), to: commented, file: "base")
    #expect(try parseMatches(yaml: after, file: "base")[1].label == nil)
}

@Test func wordsYamlWouldMisreadStayText() throws {
    let after = try applying(.add(Draft(trigger: "yes", label: "", text: "123")), to: commented, file: "base")
    let added = try parseMatches(yaml: after, file: "base").last!
    #expect(added.triggers == ["yes"])
    #expect(added.text == "123")
}

@Test func addGoesAfterLastSnippetAndKeepsTrailingComment() throws {
    let after = try applying(.add(Draft(trigger: ";new", label: "New", text: "Hello")), to: commented, file: "base")
    let s = try parseMatches(yaml: after, file: "base")
    #expect(s.count == 4)
    #expect(s[3].triggers == [";new"])
    #expect(after.hasSuffix("# trailing comment at end of file\n"))
    #expect(after.hasPrefix("# Firm snippets — keep this header\n"))
}

@Test func addToFileWithoutMatches() throws {
    let after = try applying(.add(Draft(trigger: ";a", label: "", text: "A")), to: "# empty\n", file: "new")
    #expect(try parseMatches(yaml: after, file: "new").map(\.triggers) == [[";a"]])
    #expect(after.hasPrefix("# empty\n"))
}

@Test func deleteRemovesOnlyThatSnippet() throws {
    let after = try applying(.delete(index: 0), to: commented, file: "base")
    let s = try parseMatches(yaml: after, file: "base")
    #expect(s.map(\.triggers) == [[";mcl"], [";ip"]])
    #expect(after.contains("# --- Signatures ---"))
    #expect(after.contains("# --- Discovery ---"))
}

@Test func multipleTriggersEditFirstOnly() throws {
    let yaml = "matches:\n  - triggers: [\";a\", \";b\"]\n    replace: \"x\"\n"
    let after = try applying(.update(index: 0, Draft(trigger: ";z", label: "", text: "x")), to: yaml, file: "f")
    #expect(try parseMatches(yaml: after, file: "f")[0].triggers == [";z", ";b"])
}

@Test func commandSnippetsCannotBeEdited() {
    #expect(throws: EditError.runsCommand) {
        try applying(.update(index: 2, Draft(trigger: ";ip", label: "", text: "x")), to: commented, file: "base")
    }
}

@Test func flowStyleFilesAreRefused() {
    #expect(throws: EditError.unsupportedLayout) {
        try applying(.delete(index: 0), to: "matches: [{trigger: \";a\", replace: \"b\"}]\n", file: "f")
    }
}

@Test func validationCatchesBlankAndDuplicateShortcuts() throws {
    let library = try parseMatches(yaml: commented, file: "base")
    #expect(throws: EditError.emptyTrigger) { try validate(Draft(trigger: " ", label: "", text: "x"), in: library) }
    #expect(throws: EditError.emptyText) { try validate(Draft(trigger: ";q", label: "", text: ""), in: library) }
    #expect(throws: EditError.duplicateTrigger(";mcl")) {
        try validate(Draft(trigger: ";mcl", label: "", text: "x"), in: library)
    }
    // Keeping a snippet's own shortcut is not a duplicate.
    try validate(Draft(trigger: ";mcl", label: "", text: "x"), in: library, editing: library[1].id)
}

@Test func saveBacksUpFirstAndRestoreUndoes() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let (match, backups) = (root.appending(path: "match"), root.appending(path: "backups"))
    try FileManager.default.createDirectory(at: match, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let file = match.appending(path: "base.yml")
    try commented.write(to: file, atomically: true, encoding: .utf8)

    try save(.delete(index: 0), file: "base", matchFolder: match, backups: backups)

    #expect(try loadLibrary(from: match).snippets.count == 2)
    let saved = listBackups(in: backups)
    #expect(saved.count == 1)
    #expect(saved[0].file == "base")
    #expect(try String(contentsOf: saved[0].url, encoding: .utf8) == commented)

    try restore(saved[0], matchFolder: match, backups: backups)

    #expect(try String(contentsOf: file, encoding: .utf8) == commented)
    #expect(listBackups(in: backups).count == 2) // the restore backed up the state it replaced
}

@Test func saveRefusesWhenFileChangedSinceShown() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appending(path: "base.yml")
    try commented.write(to: file, atomically: true, encoding: .utf8)
    let shown = try loadLibrary(from: root).snippets[0]
    try commented.replacingOccurrences(of: ";sig", with: ";other").write(to: file, atomically: true, encoding: .utf8)

    #expect(throws: EditError.fileChangedElsewhere) {
        try save(.delete(index: 0), file: "base", shown: shown, matchFolder: root, backups: root.appending(path: "b"))
    }
    #expect(try String(contentsOf: file, encoding: .utf8).contains(";other"))
}

@Test func saveThroughSymlinkUpdatesTheRealFile() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let (match, real) = (root.appending(path: "match"), root.appending(path: "synced/base.yml"))
    try FileManager.default.createDirectory(at: match, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: real.deletingLastPathComponent(), withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try commented.write(to: real, atomically: true, encoding: .utf8)
    let link = match.appending(path: "base.yml")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)

    try save(.delete(index: 0), file: "base", matchFolder: match, backups: root.appending(path: "b"))

    #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: link.path)) != nil) // still a link
    #expect(try parseMatches(yaml: String(contentsOf: real, encoding: .utf8), file: "base").count == 2)
}

@Test func notesBetweenASnippetsSettingsSurviveAnEdit() throws {
    let yaml = """
    matches:
      - trigger: ";a"
        # update after the sample ruling
        replace: |
          Line one
          # letter text, not a note
      - trigger: ";b"
        replace: "B"

    """
    let after = try applying(.update(index: 0, Draft(trigger: ";a", label: "", text: "New\n# still letter text")),
                             to: yaml, file: "f")
    #expect(after.contains("    # update after the sample ruling"))
    #expect(!after.contains("# letter text, not a note")) // the old text was replaced, not kept as a note
    #expect(try parseMatches(yaml: after, file: "f").map(\.text) == ["New\n# still letter text", "B"])
}

@Test func windowsLineEndingsCanBeEdited() throws {
    let yaml = commented.replacingOccurrences(of: "\n", with: "\r\n")
    var draft = Draft(try parseMatches(yaml: yaml, file: "base")[1])
    draft.text = "Changed"
    let after = try applying(.update(index: 1, draft), to: yaml, file: "base")
    let s = try parseMatches(yaml: after, file: "base")
    #expect(s.map(\.triggers) == [[";sig"], [";mcl"], [";ip"]])
    #expect(s[1].text == "Changed")
    #expect(after.contains("# trailing comment at end of file\r\n"))
}

@Test func snippetsWrittenAtTheLeftEdgeEditCleanly() throws {
    // Same sample, but with `- trigger:` in the first column, which YAML also allows.
    let leftEdge = commented.split(separator: "\n", omittingEmptySubsequences: false)
        .map { $0.hasPrefix("  ") ? String($0.dropFirst(2)) : String($0) }.joined(separator: "\n")
    let updated = try applying(.update(index: 0, Draft(trigger: ";sig", label: "", text: "Changed")),
                               to: leftEdge, file: "base")
    #expect(updated.components(separatedBy: "# --- Discovery ---")[1] == leftEdge.components(separatedBy: "# --- Discovery ---")[1])
    #expect(try parseMatches(yaml: updated, file: "base").map(\.text).first == "Changed")

    let deleted = try applying(.delete(index: 1), to: leftEdge, file: "base")
    #expect(try parseMatches(yaml: deleted, file: "base").map(\.triggers) == [[";sig"], [";ip"]])
    #expect(deleted.contains("# --- Discovery ---"))
    #expect(deleted.hasSuffix("# trailing comment at end of file\n"))
}

@Test func notesInsideAFormsSettingsSurviveAnEdit() throws {
    let yaml = """
    matches:
      - trigger: ";f"
        replace: "{{form1.a}}"
        vars:
          # intake fields, keep in this order
          - name: form1
            type: form
            params:
              layout: |
                Name [[a]]
                # layout text, not a note
      - trigger: ";g"
        replace: "G"

    """
    var draft = Draft(try parseMatches(yaml: yaml, file: "f")[0])
    draft.text = "Changed {{form1.a}}"
    let after = try applying(.update(index: 0, draft), to: yaml, file: "f")
    #expect(after.contains("# intake fields, keep in this order"))
    #expect(after.components(separatedBy: "# layout text, not a note").count == 2) // still text, not copied as a note
    let s = try parseMatches(yaml: after, file: "f")
    #expect(s[0].questions.map(\.name) == ["a"])
    #expect(s.map(\.text) == ["Changed {{form1.a}}", "G"])
}

@Test func rawYAMLShowsOnlyThatSnippetsLines() throws {
    let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    try commented.write(to: dir.appending(path: "base.yml"), atomically: true, encoding: .utf8)
    let library = try loadLibrary(from: dir).snippets

    let raw = try #require(rawYAML(of: library[1], matchFolder: dir))

    #expect(raw.hasPrefix("  - trigger: \";mcl\""))
    #expect(raw.contains("layout: \"Counsel [[counsel]]\""))
    #expect(!raw.contains(";sig"))
    #expect(!raw.contains(";ip"))
    #expect(rawYAML(of: library[1], matchFolder: dir.appending(path: "missing")) == nil)
}

@Test func patternTriggeredSnippetsAreNotEditable() throws {
    let yaml = "matches:\n  - regex: \":hi(?P<n>\\\\d)\"\n    replace: \"x\"\n"
    let draft = Draft(try parseMatches(yaml: yaml, file: "f")[0])
    #expect(throws: EditError.noPlainShortcut) { try applying(.update(index: 0, draft), to: yaml, file: "f") }
}

@Test func addingToAnEmptyMatchesListWorks() throws {
    let yaml = "matches:\n  - trigger: \";a\"\n    replace: \"A\"\n"
    let emptied = try applying(.delete(index: 0), to: yaml, file: "f")
    #expect(emptied == "matches:\n")

    let added = try applying(.add(Draft(trigger: ";b", label: "", text: "B")), to: emptied, file: "f")

    #expect(try parseMatches(yaml: added, file: "f").map(\.triggers) == [[";b"]])
    #expect(added.components(separatedBy: "matches:").count == 2) // no second `matches:` key
}

@Test func editKeepsTheSnippetsOtherSettings() throws {
    let yaml = """
    matches:
      - trigger: ";w"
        word: true
        propagate_case: true
        replace: "On {{d}}"
        vars:
          - name: d
            type: date
            params:
              format: "%d.%m.%Y"

    """
    var draft = Draft(try parseMatches(yaml: yaml, file: "f")[0])
    draft.text = "Changed {{d}}"
    let after = try applying(.update(index: 0, draft), to: yaml, file: "f")
    #expect(after.contains("word: true"))
    #expect(after.contains("propagate_case: true"))
    #expect(try parseMatches(yaml: after, file: "f")[0].dateFormats["d"] == "%d.%m.%Y")
}

@Test func restoreRefusesABrokenBackupAndLeavesTheFileAlone() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let (match, backups) = (root.appending(path: "match"), root.appending(path: "backups"))
    try FileManager.default.createDirectory(at: match, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: backups, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try commented.write(to: match.appending(path: "base.yml"), atomically: true, encoding: .utf8)
    let broken = backups.appending(path: "base @ 2026-01-01 00.00.00.000.yml")
    try "- just a list\n".write(to: broken, atomically: true, encoding: .utf8)

    #expect(throws: LibraryError.self) {
        try restore(Backup(url: broken, file: "base", date: .now), matchFolder: match, backups: backups)
    }

    #expect(try String(contentsOf: match.appending(path: "base.yml"), encoding: .utf8) == commented)
    #expect(listBackups(in: backups).count == 1) // nothing new was backed up either
}

@Test func oneUnreadableFileDoesNotHideTheOthers() throws {
    let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    try commented.write(to: dir.appending(path: "base.yml"), atomically: true, encoding: .utf8)
    try "- just a list\n".write(to: dir.appending(path: "odd.yml"), atomically: true, encoding: .utf8)

    let library = try loadLibrary(from: dir)

    #expect(library.snippets.count == 3)
    #expect(library.problems.count == 1)
    #expect(library.problems[0].hasPrefix("odd.yml:"))
}

@Test func packageSnippetsAreShownButNeverEdited() throws {
    let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let pkg = dir.appending(path: "packages/p1")
    try FileManager.default.createDirectory(at: pkg, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    try "matches:\n  - trigger: \":pk\"\n    replace: \"P\"\n".write(to: pkg.appending(path: "package.yml"), atomically: true, encoding: .utf8)
    try "name: p1\n".write(to: pkg.appending(path: "_manifest.yml"), atomically: true, encoding: .utf8)
    try commented.write(to: dir.appending(path: "base.yml"), atomically: true, encoding: .utf8)

    let library = try loadLibrary(from: dir)

    #expect(library.problems.isEmpty) // `_manifest.yml` is skipped like Espanso does
    let package = try #require(library.snippets.first { $0.triggers == [":pk"] })
    #expect(package.file == "packages/p1/package")
    #expect(package.inSubfolder)
    #expect(library.snippets.filter(\.inSubfolder).count == 1)
    #expect(throws: EditError.packageFile) {
        try save(.delete(index: 0), file: package.file, matchFolder: dir, backups: dir.appending(path: "b"))
    }
    #expect(rawYAML(of: package, matchFolder: dir)?.contains(":pk") == true)
}

@Test func onlyTheNewestBackupsAreKept() throws {
    let backups = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: backups) }

    for n in 1...(backupsKept + 5) { try backUp("version \(n)", file: "base", to: backups) }

    let kept = listBackups(in: backups)
    #expect(kept.count == backupsKept)
    #expect(try String(contentsOf: kept[0].url, encoding: .utf8) == "version \(backupsKept + 5)")
    #expect(try String(contentsOf: kept[backupsKept - 1].url, encoding: .utf8) == "version 6")
}

@Test func duplicateKeepsTheOriginalsOtherSettings() throws {
    let yaml = """
    matches:
      - triggers: [";hd", ";hearing"]
        label: "Hearing date"
        markdown: "**Hearing:** {{date}}"
        word: true
        vars:
          - name: date
            type: date
            params:
              format: "%m/%d/%Y"
    """
    let original = try parseMatches(yaml: yaml, file: "base")[0]
    var draft = Draft(original)
    draft.trigger = ";hd2"
    draft.label = "Hearing date copy"
    let after = try applying(.add(draft, copying: 0), to: yaml, file: "base")
    let copy = try parseMatches(yaml: after, file: "base")[1]
    #expect(copy.triggers == [";hd2"])
    #expect(copy.dateFormats["date"] == "%m/%d/%Y")
    #expect(rawYAMLLines(after, snippet: 1).contains { $0.contains("markdown:") })
    #expect(rawYAMLLines(after, snippet: 1).contains { $0.contains("word: true") })
    #expect(try parseMatches(yaml: after, file: "base")[0].triggers == [";hd", ";hearing"]) // original untouched
}

private func rawYAMLLines(_ yaml: String, snippet index: Int) -> [String] {
    yaml.components(separatedBy: "\n  - ").dropFirst()[index + 1].components(separatedBy: "\n")
}
