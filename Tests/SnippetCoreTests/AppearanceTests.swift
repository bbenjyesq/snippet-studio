import Foundation
import Testing
@testable import SnippetCore

private let two = try! parseMatches(yaml: """
matches:
  - trigger: ":mc"
    replace: "Dear counsel"
  - regex: "x+"
    replace: "y"
""", file: "base")

@Test func groupAndIconFollowAShortcutChange() {
    var look = Appearance()
    let discovery = SnippetGroup(name: "Discovery", color: "blue")
    look.groups = [discovery]
    look.groupOf[":mc"] = discovery.id
    look.iconOf[":mc"] = "envelope.fill"
    look.editedAt[":mc"] = .distantPast

    #expect(look.group(of: two[0]) == discovery)
    look.move(from: ":mc", to: ":meet")
    #expect(look.groupOf == [":meet": discovery.id])
    #expect(look.iconOf == [":meet": "envelope.fill"])
    #expect(look.editedAt == [":meet": .distantPast])
    look.forget(":meet")
    #expect(look.groupOf.isEmpty && look.iconOf.isEmpty && look.editedAt.isEmpty)
    #expect(look.groups == [discovery])
}

@Test func deletingAGroupOnlyUngroups() {
    var look = Appearance()
    let a = SnippetGroup(name: "A", color: "red"), b = SnippetGroup(name: "B", color: "green")
    look.groups = [a, b]
    look.groupOf = [":x": a.id, ":y": b.id]
    look.iconOf = [":x": "star.fill"]
    look.deleteGroup(a.id)
    #expect(look.groups == [b])
    #expect(look.groupOf == [":y": b.id])
    #expect(look.iconOf == [":x": "star.fill"])
}

@Test func snippetWithoutShortcutIsKnownByPosition() {
    #expect(appearanceKey(two[0]) == ":mc")
    #expect(appearanceKey(two[1]) == "base#1")
}

@Test func savesLoadsAndSetsAsideAnUnreadableFile() throws {
    let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let url = dir.appending(path: "appearance.json")
    #expect(loadAppearance(from: url) == Appearance()) // first run: no file yet

    var look = Appearance()
    look.groups = [SnippetGroup(name: "Citations", color: "purple")]
    look.groupOf[":ccp"] = look.groups[0].id
    try saveAppearance(look, to: url)
    #expect(loadAppearance(from: url) == look)

    var changed = look
    changed.iconOf[":ccp"] = "star.fill"
    try saveAppearance(changed, to: url)
    #expect(loadAppearance(from: url) == changed)
    #expect(loadAppearance(from: dir.appending(path: "appearance (previous).json")) == look) // one step back is kept

    for text in ["not json", "still not json"] {
        try text.write(to: url, atomically: true, encoding: .utf8)
        #expect(loadAppearance(from: url) == Appearance())
    }
    let setAside = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasPrefix("appearance (unreadable") }
    let kept = try setAside.map { try String(contentsOf: dir.appending(path: $0), encoding: .utf8) }
    #expect(Set(kept) == ["not json", "still not json"]) // the second never replaces the first
}

@Test func aFileMissingAFieldStillLoads() throws {
    let data = Data(#"{"groups":[{"id":"11111111-2222-3333-4444-555555555555","name":"Discovery","color":"blue"}]}"#.utf8)
    let look = try JSONDecoder().decode(Appearance.self, from: data)
    #expect(look.groups.map(\.name) == ["Discovery"])
    #expect(look.groupOf.isEmpty && look.iconOf.isEmpty && look.editedAt.isEmpty)
}
