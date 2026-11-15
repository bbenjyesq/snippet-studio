import Foundation
import Testing
@testable import SnippetCore

let sample = """
matches:
  - trigger: ";sig"
    replace: "Example Law Group"
  - trigger: ";mcl"
    label: "Meet and confer"
    replace: "Dear {{form1.counsel}}: re {{form1.set}} on {{today}}"
    vars:
      - name: today
        type: date
        params:
          format: "%B %e, %Y"
      - name: form1
        type: form
        params:
          layout: "Counsel [[counsel]] Set [[set]] Notes [[notes]]"
          fields:
            set:
              type: choice
              values:
                - Special Interrogatories
                - Requests for Production
            notes:
              multiline: true
  - triggers: [";a", ";b"]
    form: "Hello [[name]]"
  - trigger: ";ip"
    replace: "{{out}}"
    vars:
      - name: out
        type: shell
        params:
          cmd: "echo hi"
"""

@Test func parsesTriggersLabelsAndQuestions() throws {
    let s = try parseMatches(yaml: sample, file: "base")
    #expect(s.count == 4)
    #expect(s[0].title == ";sig")
    #expect(s[1].title == "Meet and confer")
    #expect(s[1].questions == [
        Question(name: "counsel", kind: "text", prompt: "Counsel"),
        Question(name: "set", kind: "choice", options: ["Special Interrogatories", "Requests for Production"], prompt: "Set"),
        Question(name: "notes", kind: "multi-line text", prompt: "Notes"),
    ])
    #expect(s[1].variables["today"] == "date")
    #expect(s[1].dateFormats["today"] == "%B %e, %Y")
    #expect(s[1].formName == "form1")
    #expect(s[1].questionsEditable)
    #expect(!s[2].questionsEditable) // Espanso's `form:` shorthand
    #expect(s[2].triggers == [";a", ";b"])
    #expect(s[2].questions.map(\.name) == ["name"])
    #expect(s[3].runsCommand)
    #expect(!s[1].runsCommand)
}

@Test func choiceValuesMayBeOnePerLine() {
    #expect(values("A\n  B\n\n") == ["A", "B"])
}

@Test func splitsTokens() {
    #expect(segments("Hi {{form1.name}} [[x]] {{today}}!") == [
        .text("Hi "), .token(name: "form1.name", isQuestion: true), .text(" "),
        .token(name: "x", isQuestion: true), .text(" "),
        .token(name: "today", isQuestion: false), .text("!"),
    ])
}

@Test func rejectsNonMatchFile() {
    #expect(throws: LibraryError.self) { try parseMatches(yaml: "- just a list", file: "bad") }
}

@Test func loadsOnlyVisibleYmlFilesAndNeverWrites() throws {
    let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    try sample.write(to: dir.appending(path: "base.yml"), atomically: true, encoding: .utf8)
    try sample.write(to: dir.appending(path: "_hidden.yml"), atomically: true, encoding: .utf8)
    try "notes".write(to: dir.appending(path: "readme.txt"), atomically: true, encoding: .utf8)
    let before = try Data(contentsOf: dir.appending(path: "base.yml"))

    let library = try loadLibrary(from: dir).snippets

    #expect(library.count == 4)
    #expect(Set(library.map(\.file)) == ["base"])
    #expect(try Data(contentsOf: dir.appending(path: "base.yml")) == before)
}

// A regression here would trap (abort the whole test run) rather than fail one test.
@Test func numberLikeValuesLoadAsTextInsteadOfCrashing() throws {
    let yaml = """
    matches:
      - trigger: 200000000000000000:1
        replace: 1:1:1:1:1:1:1:1:1:1:1
      - trigger: 123
        replace: "x"
        vars:
          - name: pick
            type: choice
            params:
              values: [1, 2.5]
    """
    let s = try parseMatches(yaml: yaml, file: "f")
    #expect(s.map(\.triggers) == [["200000000000000000:1"], ["123"]])
    #expect(s[0].text == "1:1:1:1:1:1:1:1:1:1:1")
    #expect(s[1].questions.first?.options == ["1", "2.5"])
}

// Each of these used to abort the whole app inside Yams (found by the security scan); now they load as text or are skipped.
@Test func packageFilesThatCrashedYamsLoadSafely() throws {
    let yaml = """
    matches:
      - trigger: ":a"
        replace: !!int 1:0:0:0:0:0:0:0:0:0:0
      - trigger: !!float 1:0:0:0:0:0:0:0:0:0:0.5
        replace: "b"
        multiline: true
    ? [complex, key]
    : 1
    other: {[x]: 1}
    """
    let s = try parseMatches(yaml: yaml, file: "packages/evil/package")
    #expect(s.map(\.triggers) == [[":a"], ["1:0:0:0:0:0:0:0:0:0:0.5"]])
    #expect(s[0].text == "1:0:0:0:0:0:0:0:0:0:0")
}

@Test func yesNoAndEmptyValuesReadLikeEspanso() throws {
    let s = try parseMatches(yaml: """
    matches:
      - trigger: yes
        label: ~
        replace: no
    """, file: "f")
    #expect(s[0].triggers == ["yes"])
    #expect(s[0].label == nil)
    #expect(s[0].text == "no")
}
