import Foundation
import Testing
@testable import SnippetCore

// Invented sample only — never real snippets (see docs/PLAN.md, Security rules).

@Test func newSnippetWithQuestionsDateAndClipboardIsWrittenForEspanso() throws {
    var draft = Draft(trigger: ";mc", label: "Meet and confer", text: "")
    let counsel = draft.addQuestion(prompt: "Opposing counsel", kind: "text", options: [])
    let set = draft.addQuestion(prompt: "Discovery set", kind: "choice", options: ["Special Interrogatories", "RFPs"])
    let notes = draft.addQuestion(prompt: "Notes", kind: "multi-line text", options: [])
    draft.text = "{{date}}\nDear \(counsel): re \(set).\n\(notes)\n{{clipboard}}$|$"

    let after = try applying(.add(draft), to: "matches:\n  - trigger: \";x\"\n    replace: \"x\"\n", file: "base")
    let s = try parseMatches(yaml: after, file: "base")[1]

    #expect(counsel == "{{form1.opposing_counsel}}")
    #expect(s.questions == draft.questions)
    #expect(s.questions.map(\.prompt) == ["Opposing counsel", "Discovery set", "Notes"])
    #expect(s.variables == ["form1": "form", "date": "date", "clipboard": "clipboard"])
    #expect(s.dateFormats["date"] == defaultDateFormat)
    #expect(s.text == draft.text)
    #expect(s.questionsEditable)
}

@Test func untouchedFormKeepsItsExactLayout() throws {
    let yaml = """
    matches:
      - trigger: ";f"
        replace: "{{form1.a}}"
        vars:
          - name: form1
            type: form
            params:
              layout: "Client: [[a]]   (as on the retainer)"

    """
    let draft = Draft(try parseMatches(yaml: yaml, file: "f")[0])
    var changed = draft
    changed.text = "Changed {{form1.a}}"
    let after = try applying(.update(index: 0, changed), to: yaml, file: "f")
    #expect(after.contains("Client: [[a]]   (as on the retainer)"))
}

@Test func editingQuestionsRewritesTheForm() throws {
    let yaml = """
    matches:
      - trigger: ";f"
        replace: "{{form1.a}} {{form1.b}}"
        vars:
          - name: form1
            type: form
            params:
              layout: "First [[a]] Second [[b]]"

    """
    var draft = Draft(try parseMatches(yaml: yaml, file: "f")[0])
    draft.removeQuestion(named: "b")
    let added = draft.addQuestion(prompt: "Hearing department", kind: "text", options: [])
    draft.text += added
    #expect(!draft.text.contains("{{form1.b}}"))

    let s = try parseMatches(yaml: applying(.update(index: 0, draft), to: yaml, file: "f"), file: "f")[0]
    #expect(s.questions.map(\.name) == ["a", "hearing_department"])
    #expect(s.questions.map(\.prompt) == ["First", "Hearing department"])
}

@Test func removingTheLastQuestionRemovesTheForm() throws {
    let yaml = "matches:\n  - trigger: \";f\"\n    replace: \"{{form1.a}}\"\n    vars:\n      - name: form1\n        type: form\n        params:\n          layout: \"A [[a]]\"\n"
    var draft = Draft(try parseMatches(yaml: yaml, file: "f")[0])
    draft.removeQuestion(named: "a")
    draft.text = "Plain"
    let s = try parseMatches(yaml: applying(.update(index: 0, draft), to: yaml, file: "f"), file: "f")[0]
    #expect(s.variables.isEmpty)
    #expect(s.questions.isEmpty)
}

@Test func questionsFromTwoPlacesAreLeftAlone() throws {
    let yaml = "matches:\n  - trigger: \";f\"\n    replace: \"{{pick}}\"\n    vars:\n      - name: pick\n        type: choice\n        params:\n          values: [A, B]\n"
    var draft = Draft(try parseMatches(yaml: yaml, file: "f")[0])
    _ = draft.addQuestion(prompt: "Extra", kind: "text", options: [])
    #expect(throws: EditError.questionsNotEditable) { try applying(.update(index: 0, draft), to: yaml, file: "f") }
}

@Test func questionNamesAreUniqueAndSafe() {
    var draft = Draft(trigger: ";a", label: "", text: "")
    #expect(draft.addQuestion(prompt: "Client's name", kind: "text", options: []) == "{{form1.client_s_name}}")
    #expect(draft.addQuestion(prompt: "Client's name", kind: "text", options: []) == "{{form1.client_s_name_2}}")
    #expect(draft.addQuestion(prompt: "2nd party", kind: "text", options: []) == "{{form1.q2nd_party}}")
}

@Test func previewFillsAnswersDatesAndPlaceholders() {
    let noon = Date(timeIntervalSince1970: 1_793_102_400) // 2026-10-27 12:00 GMT
    let text = "Dear {{form1.counsel}}, on {{date}} re {{form1.set}} {{clipboard}} {{out}}$|$."
    let shown = preview(text, variables: ["out": "shell"], dateFormats: [:],
                        answers: ["counsel": "Ms. Lee", "set": ""], now: noon, timeZone: .gmt)
    #expect(shown == "Dear Ms. Lee, on October 27, 2026 re [set] [clipboard] [out].")
}

@Test func strftimeFormats() {
    let noon = Date(timeIntervalSince1970: 1_793_102_400)
    #expect(formatDate(noon, strftime: "%m/%d/%Y", timeZone: .gmt) == "10/27/2026")
    #expect(formatDate(noon, strftime: "%A, %B %e, %Y", timeZone: .gmt) == "Tuesday, October 27, 2026")
    #expect(formatDate(noon, strftime: "Dated: %-m/%-d/%y", timeZone: .gmt) == "Dated: 10/27/26")
}

@Test func addingAQuestionKeepsDefaultsAndExtraFormText() throws {
    let yaml = """
    matches:
      - trigger: ";f"
        replace: "{{form1.city}}"
        vars:
          - name: form1
            type: form
            params:
              layout: "City [[city]]  (as on the retainer)"
              fields:
                city:
                  default: "Los Angeles"

    """
    var draft = Draft(try parseMatches(yaml: yaml, file: "f")[0])
    let department = draft.addQuestion(prompt: "Department", kind: "text", options: [])
    draft.text += " " + department
    let after = try applying(.update(index: 0, draft), to: yaml, file: "f")
    #expect(after.contains("default: \"Los Angeles\""))
    #expect(after.contains("City [[city]]  (as on the retainer)"))
    #expect(try parseMatches(yaml: after, file: "f")[0].questions.map(\.prompt) == ["City", "Department"])
}

@Test func sharedDateIsNotOverriddenByAnEdit() throws {
    let yaml = """
    global_vars:
      - name: date
        type: date
        params:
          format: "%m/%d/%Y"
    matches:
      - trigger: ";d"
        replace: "Dated {{date}}"

    """
    let s = try parseMatches(yaml: yaml, file: "f")[0]
    #expect(s.dateFormats["date"] == "%m/%d/%Y") // the preview uses the shared format

    var relabeled = Draft(s)
    relabeled.label = "Date line"
    let edited = try parseMatches(yaml: applying(.update(index: 0, relabeled), to: yaml, file: "f"), file: "f")[0]
    #expect(edited.variables.isEmpty)

    let added = try applying(.add(Draft(trigger: ";e", label: "", text: "On {{date}}")), to: yaml, file: "f")
    #expect(try parseMatches(yaml: added, file: "f")[1].variables.isEmpty)
}

@Test func questionsNamedLikeYesOrNoStillSave() throws {
    var draft = Draft(trigger: ";y", label: "", text: "")
    let yes = draft.addQuestion(prompt: "Yes", kind: "choice", options: ["Agreed", "Declined"])
    let on = draft.addQuestion(prompt: "On", kind: "multi-line text", options: [])
    draft.text = yes + on
    let after = try applying(.add(draft), to: "matches:\n  - trigger: \";x\"\n    replace: \"x\"\n", file: "f")
    #expect(try parseMatches(yaml: after, file: "f")[1].questions == draft.questions)
}

@Test func spacePaddedDayMatchesWhatEspansoTypes() {
    let fifth = Date(timeIntervalSince1970: 1_791_201_600) // 2026-10-05 12:00 GMT
    #expect(formatDate(fifth, strftime: "%B %e, %Y", timeZone: .gmt) == "October  5, 2026")
    #expect(formatDate(fifth, strftime: "%B %-d, %Y", timeZone: .gmt) == "October 5, 2026")
    #expect(formatDate(fifth, strftime: "%d.%m.%Y 100%%", timeZone: .gmt) == "05.10.2026 100%")
}

@Test func removingAQuestionAlsoRemovesItsPlaceholderWrittenWithSpaces() {
    var draft = Draft(trigger: ";a", label: "", text: "Dear {{ form1.counsel }}: re {{form1.set}}.")
    _ = draft.addQuestion(prompt: "Counsel", kind: "text", options: [])
    _ = draft.addQuestion(prompt: "Set", kind: "text", options: [])
    draft.removeQuestion(named: "counsel")
    #expect(draft.text == "Dear : re {{form1.set}}.")
    #expect(draft.questions.map(\.name) == ["set"])
}
