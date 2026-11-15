import Foundation
import Yams

/// What the editor lets a person change: the shortcut, the name, the text it types and the questions it asks.
public struct Draft: Equatable, Sendable {
    public var trigger: String
    public var label: String
    public var text: String
    public var questions: [Question]
    /// Answers appear in the text as `{{formName.field}}`.
    public var formName: String

    public init(trigger: String, label: String, text: String, questions: [Question] = [], formName: String = "form1") {
        self.trigger = trigger
        self.label = label
        self.text = text
        self.questions = questions
        self.formName = formName
    }

    public init(_ snippet: Snippet) {
        self.init(trigger: snippet.triggers.first ?? "", label: snippet.label ?? "", text: snippet.text,
                  questions: snippet.questions, formName: snippet.formName ?? "form1")
    }

    /// Adds a question and returns the `{{form.field}}` token to put in the text.
    public mutating func addQuestion(prompt: String, kind: String, options: [String]) -> String {
        let prompt = prompt.trimmingCharacters(in: .whitespaces) // the saved form reads prompts back trimmed
        var name = prompt.lowercased().replacing(/[^a-z0-9]+/, with: "_").trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        if name.isEmpty || name.first!.isNumber { name = "q" + name }
        let base = name
        var n = 2
        while questions.contains(where: { $0.name == name }) { name = "\(base)_\(n)"; n += 1 }
        questions.append(Question(name: name, kind: kind, options: options, prompt: prompt.isEmpty ? nil : prompt))
        return "{{\(formName).\(name)}}"
    }

    /// Removes a question and every place its answer appears in the text, with or without spaces inside the braces.
    public mutating func removeQuestion(named name: String) {
        questions.removeAll { $0.name == name }
        let token = NSRegularExpression.escapedPattern(for: "\(formName).\(name)")
        if let regex = try? Regex(#"\{\{\s*"# + token + #"\s*\}\}"#) { text = text.replacing(regex, with: "") }
    }
}

/// Espanso date format used by the "Today's date" button: "October 27, 2026".
public let defaultDateFormat = "%B %-d, %Y"

public enum Change: Sendable {
    /// `copying` is the index of a snippet in the same file whose other settings the new one starts from (Duplicate).
    case add(Draft, copying: Int? = nil)
    case update(index: Int, Draft)
    case delete(index: Int)
}

public enum EditError: LocalizedError, Equatable {
    case emptyTrigger, emptyText, duplicateTrigger(String), runsCommand, unsupportedLayout, wouldAlterOtherSnippets
    case fileChangedElsewhere, questionsNotEditable, noPlainShortcut, packageFile

    public var errorDescription: String? {
        switch self {
        case .emptyTrigger: "Please enter the shortcut you’ll type."
        case .emptyText: "Please enter the text the snippet should type."
        case .duplicateTrigger(let t): "Another snippet already uses the shortcut “\(t)”."
        case .runsCommand: "Snippets that run a computer command can’t be edited here."
        case .unsupportedLayout: "This file is laid out in a way the editor can’t safely change. Nothing was saved."
        case .wouldAlterOtherSnippets: "Saving would have changed other snippets, so nothing was saved."
        case .fileChangedElsewhere: "The snippet file changed outside Snippet Studio. Click Reload, then try again."
        case .noPlainShortcut: "This snippet has no plain shortcut (it may be triggered by a pattern), which the editor can’t change yet."
        case .packageFile: "This snippet belongs to an Espanso package, which Espanso manages. It can’t be changed here."
        case .questionsNotEditable: "This snippet’s questions are set up in a way the editor can’t change yet. Its name, shortcut and text can still be edited."
        }
    }
}

/// Checks a draft against the rest of the library before any file is touched.
public func validate(_ draft: Draft, in library: [Snippet], editing id: Snippet.ID? = nil) throws {
    let trigger = draft.trigger.trimmingCharacters(in: .whitespaces)
    guard !trigger.isEmpty else { throw EditError.emptyTrigger }
    guard !draft.text.isEmpty else { throw EditError.emptyText }
    if library.contains(where: { $0.id != id && $0.triggers.contains(trigger) }) {
        throw EditError.duplicateTrigger(trigger)
    }
}

/// The validation problem as a message for the screen, or nil when the draft can be saved.
public func validationProblem(_ draft: Draft, in library: [Snippet], editing id: Snippet.ID? = nil) -> String? {
    do { try validate(draft, in: library, editing: id); return nil } catch { return error.localizedDescription }
}

/// Returns the file's new text with only the changed snippet's lines rewritten.
/// Comments and every other line stay byte-for-byte identical.
public func applying(_ change: Change, to original: String, file: String) throws -> String {
    // Swift treats "\r\n" as one character, so edit with "\n" endings and put Windows endings back at the end.
    let crlf = original.contains("\r\n")
    let yaml = crlf ? original.replacingOccurrences(of: "\r\n", with: "\n") : original
    var lines = yaml.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    let items = try matchItems(yaml, lines: lines)

    switch change {
    case .add(let draft, let source):
        var base = Node.Mapping([])
        var oldQuestions: [Question] = []
        var skip = try globalVariables(yaml)
        if let source {
            // A copy keeps everything the editor doesn't show (date formats, formatting, form defaults, `word`, ...).
            guard items.indices.contains(source) else { throw EditError.unsupportedLayout }
            try guardEditable(items[source].node)
            let parsed = try parseMatches(yaml: yaml, file: file)
            guard parsed.indices.contains(source) else { throw EditError.unsupportedLayout }
            // Shortcut first, as in any new snippet; only the new shortcut (the original's others stay the original's).
            var pairs: [(Node, Node)] = [("trigger", Node(""))]
            for (key, value) in items[source].node where key.string != "trigger" && key.string != "triggers" {
                pairs.append((key, value))
            }
            base = Node.Mapping(pairs)
            oldQuestions = parsed[source].questions
            skip.formUnion(["date", "clipboard"].filter { parsed[source].text.contains("{{\($0)}}") })
        }
        let text = try render(entry(merging: draft, into: base, oldQuestions: oldQuestions, skipVars: skip),
                              indent: items.last?.indent ?? 2)
        if let last = items.last {
            lines.insert(contentsOf: text, at: last.lines.upperBound)
        } else if let matches = try Yams.compose(yaml: yaml)?["matches"] {
            // `matches:` with nothing under it, which is what deleting the last snippet leaves: add right after that line.
            guard matches.scalar?.string == "", let at = lines.firstIndex(where: { $0.hasPrefix("matches:") })
            else { throw EditError.unsupportedLayout } // e.g. `matches: []`
            lines.insert(contentsOf: text, at: at + 1)
        } else {
            if lines.last == "" { lines.removeLast() }
            lines += ["matches:"] + text + [""]
        }
    case .update(let index, let draft):
        guard items.indices.contains(index) else { throw EditError.unsupportedLayout }
        try guardEditable(items[index].node)
        let item = items[index]
        let parsed = try parseMatches(yaml: yaml, file: file)
        guard parsed.indices.contains(index) else { throw EditError.unsupportedLayout }
        let old = parsed[index]
        if draft.questions != old.questions && !old.questionsEditable { throw EditError.questionsNotEditable }
        // Only fill-ins new in this edit get a variable; one already in the text may use a shared `global_vars` entry.
        let skip = try globalVariables(yaml).union(["date", "clipboard"].filter { old.text.contains("{{\($0)}}") })
        let text = try render(entry(merging: draft, into: item.node, oldQuestions: old.questions, skipVars: skip),
                              indent: item.indent)
        // Re-indented to the snippet's settings so a note can never fall into a text block above it.
        let pad = String(repeating: " ", count: item.indent + 2)
        let kept = notes(in: lines[item.lines]).map { pad + $0.trimmingCharacters(in: .whitespaces) }
        lines.replaceSubrange(item.lines, with: text + kept)
    case .delete(let index):
        guard items.indices.contains(index) else { throw EditError.unsupportedLayout }
        lines.removeSubrange(items[index].lines)
    }

    let result = lines.joined(separator: "\n")
    try verify(change, before: yaml, after: result, file: file)
    return crlf ? result.replacingOccurrences(of: "\n", with: "\r\n") : result
}

/// A snippet's own lines from its match file, exactly as saved. Nil when the file can't be read or split safely.
public func rawYAML(of snippet: Snippet, matchFolder: URL = espansoMatchFolder) -> String? {
    guard let text = try? String(contentsOf: matchFolder.appending(path: "\(snippet.file).yml"), encoding: .utf8) else { return nil }
    let yaml = text.replacingOccurrences(of: "\r\n", with: "\n") // Swift sees "\r\n" as one character
    let lines = yaml.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    guard let items = try? matchItems(yaml, lines: lines), items.indices.contains(snippet.index) else { return nil }
    return lines[items[snippet.index].lines].joined(separator: "\n")
}

struct MatchItem {
    let node: Node.Mapping
    let lines: Range<Int>
    let indent: Int
}

func matchItems(_ yaml: String, lines: [String]) throws -> [MatchItem] {
    guard let sequence = try Yams.compose(yaml: yaml)?["matches"]?.sequence else { return [] }
    var items: [MatchItem] = []
    for node in sequence {
        guard case .mapping(let mapping) = node, let mark = mapping.mark, mark.line <= lines.count
        else { throw EditError.unsupportedLayout }
        // The mapping starts at its first key; its `- ` is on that line or just above it.
        guard let dash = (0..<mark.line).reversed().first(where: { lines[$0].trimmingCharacters(in: .whitespaces).hasPrefix("-") }),
              dash > (items.last?.lines.lowerBound ?? -1)
        else { throw EditError.unsupportedLayout } // flow style, e.g. `matches: [{...}]`
        let indent = leadingSpaces(lines[dash])
        var end = lines.indices.first { $0 > dash && !isBlankOrComment(lines[$0]) && leadingSpaces(lines[$0]) <= indent } ?? lines.count
        // Comments and blank lines after a snippet belong to the file, not the snippet. Comment-looking
        // lines indented deeper are part of a multi-line text block and stay with the snippet.
        while end - 1 > dash, isBlankOrComment(lines[end - 1]), leadingSpaces(lines[end - 1]) <= indent + 2 {
            end -= 1
        }
        items.append(MatchItem(node: mapping, lines: dash..<end, indent: indent))
    }
    return items
}

func leadingSpaces(_ line: String) -> Int { line.prefix { $0 == " " }.count }

func isBlankOrComment(_ line: String) -> Bool {
    line.trimmingCharacters(in: .whitespaces).isEmpty || isComment(line)
}

func isComment(_ line: String) -> Bool { line.trimmingCharacters(in: .whitespaces).hasPrefix("#") }

/// The `# note` lines of a snippet: every `#` line except those inside a `|` or `>` text block,
/// where `#` is just text the snippet types.
func notes(in lines: ArraySlice<String>) -> [String] {
    var blockKeyIndent: Int? // set while inside a text block: the indent of the key that opened it
    var notes: [String] = []
    for line in lines {
        if let keyIndent = blockKeyIndent,
           line.trimmingCharacters(in: .whitespaces).isEmpty || leadingSpaces(line) > keyIndent {
            continue
        }
        blockKeyIndent = nil
        if isComment(line) {
            notes.append(line)
        } else if line.contains(/[:-]\s+[|>][-+0-9]*\s*(#.*)?$/) {
            blockKeyIndent = line.prefix { $0 == " " || $0 == "-" }.count // `- replace: |` starts after the dash
        }
    }
    return notes
}

func guardEditable(_ mapping: Node.Mapping) throws {
    // A `regex:` snippet has no `trigger`; adding one next to it could make Espanso refuse the file.
    if mapping["trigger"] == nil && mapping["triggers"] == nil { throw EditError.noPlainShortcut }
    let types = (mapping["vars"]?.sequence ?? Node.Sequence([])).compactMap { $0["type"]?.string }
    if types.contains("shell") || types.contains("script") { throw EditError.runsCommand }
}

/// Names defined once for the whole file under `global_vars`.
func globalVariables(_ yaml: String) throws -> Set<String> {
    Set((try Yams.compose(yaml: yaml)?["global_vars"]?.sequence ?? []).compactMap { $0["name"]?.string })
}

/// Applies the draft to a snippet's YAML, keeping every key the editor does not handle (word, other vars, ...).
/// The form changes only when questions were added or removed, and then only for those questions.
func entry(merging draft: Draft, into original: Node.Mapping, oldQuestions: [Question], skipVars: Set<String>) -> Node.Mapping {
    var mapping = original
    var vars = mapping["vars"]?.sequence ?? Node.Sequence([])
    if draft.questions != oldQuestions {
        let removed = oldQuestions.map(\.name).filter { name in !draft.questions.contains { $0.name == name } }
        let added = draft.questions.filter { question in !oldQuestions.contains { $0.name == question.name } }
        let form = vars.firstIndex { $0["type"]?.string == "form" }
        switch (form, draft.questions.isEmpty) {
        case (let i?, true): vars.remove(at: i)
        case (let i?, false): vars[i] = updatedForm(vars[i], removing: removed, adding: added)
        case (nil, false): vars.append(formVariable(draft))
        case (nil, true): break
        }
    }
    // The Insert buttons put `{{date}}` / `{{clipboard}}` in the text; make sure Espanso knows what they mean.
    for name in ["date", "clipboard"] where draft.text.contains("{{\(name)}}") && !skipVars.contains(name)
        && !vars.contains(where: { $0["name"]?.string == name }) {
        var pairs: [(Node, Node)] = [("name", Node(name)), ("type", Node(name))]
        if name == "date" {
            pairs.append(("params", yamlMapping([("format", Node(defaultDateFormat, Tag(.str), .doubleQuoted))])))
        }
        vars.append(Node(pairs))
    }
    let trigger = Node(draft.trigger.trimmingCharacters(in: .whitespaces), Tag(.str), .doubleQuoted)
    if var triggers = mapping["triggers"]?.sequence, !triggers.isEmpty {
        triggers[triggers.startIndex] = trigger // the editor shows and edits the first shortcut
        mapping["triggers"] = .sequence(triggers)
    } else {
        mapping["trigger"] = trigger
    }
    mapping["label"] = draft.label.isEmpty ? nil : Node(draft.label, Tag(.str), .doubleQuoted)
    let textKey = ["replace", "form", "markdown", "html"].first { mapping[$0] != nil } ?? "replace"
    mapping[textKey] = Node(draft.text, Tag(.str), draft.text.contains("\n") ? .literal : .doubleQuoted)
    mapping["vars"] = vars.isEmpty ? nil : .sequence(vars) // last, so a new snippet reads trigger, label, text, vars
    return mapping
}

/// A YAML mapping from key/value pairs. The typed parameter makes Swift pick Yams's plain pair builder
/// instead of `Node(_ representable:)`, which can throw.
func yamlMapping(_ pairs: [(Node, Node)]) -> Node { Node(pairs) }

/// A new form variable asking every question in the draft, one per line: "Opposing counsel [[counsel]]".
func formVariable(_ draft: Draft) -> Node {
    updatedForm(yamlMapping([("name", Node(draft.formName)), ("type", "form")]), removing: [], adding: draft.questions)
}

/// The form with removed questions taken out and new ones added as lines. Everything else in it
/// (defaults, other field settings, extra layout text) is kept as it was.
func updatedForm(_ old: Node, removing removed: [String], adding added: [Question]) -> Node {
    guard var form = old.mapping else { return old }
    var params = form["params"]?.mapping ?? Node.Mapping([])
    var layout = params["layout"]?.string ?? ""
    var fields = params["fields"]?.mapping ?? Node.Mapping([])
    for name in removed {
        layout = removingField(name, from: layout)
        fields[name] = nil
    }
    for question in added {
        layout += (layout.isEmpty || layout.hasSuffix("\n") ? "" : "\n") + "\(question.prompt) [[\(question.name)]]"
        // Quoted, so a name like `yes` or `on` stays a name instead of becoming true/false.
        if let spec = fieldSpec(question) { fields[Node(question.name, Tag(.str), .doubleQuoted)] = spec }
    }
    params["layout"] = Node(layout, Tag(.str), layout.contains("\n") ? .literal : .doubleQuoted)
    params["fields"] = fields.isEmpty ? nil : .mapping(fields)
    form["params"] = .mapping(params)
    return .mapping(form)
}

/// Settings a new field needs beyond a short answer, which needs none.
func fieldSpec(_ question: Question) -> Node? {
    switch question.kind {
    case "choice", "list":
        yamlMapping([("type", Node(question.kind)), ("values", Node(question.options.map { Node($0, Tag(.str), .doubleQuoted) }))])
    case "multi-line text":
        yamlMapping([("multiline", Node("true"))])
    default:
        nil
    }
}

/// Takes a field, and the prompt just before it on its line, out of a form layout. Drops the line if nothing is left.
func removingField(_ name: String, from layout: String) -> String {
    var lines = layout.components(separatedBy: "\n")
    for i in lines.indices {
        var previousEnd = lines[i].startIndex
        for match in lines[i].matches(of: /\[\[\s*(\w+)\s*\]\]/) {
            if match.1 == name {
                lines[i].removeSubrange(previousEnd..<match.range.upperBound)
                if lines[i].trimmingCharacters(in: .whitespaces).isEmpty { lines.remove(at: i) }
                return lines.joined(separator: "\n")
            }
            previousEnd = match.range.upperBound
        }
    }
    return layout
}

/// Serializes one `- ...` list entry, indented to sit where the old one was.
func render(_ mapping: Node.Mapping, indent: Int) throws -> [String] {
    let yaml = try Yams.serialize(node: Node([.mapping(mapping)]), width: -1, allowUnicode: true)
    let pad = String(repeating: " ", count: indent)
    // A text ending in blank lines makes the writer add a `...` end-of-document line; it must not land mid-file.
    return yaml.split(separator: "\n", omittingEmptySubsequences: false).dropLast()
        .filter { $0 != "..." }.map { pad + $0 }
}

/// Re-reads the new text and confirms the change did exactly what was asked and nothing else.
func verify(_ change: Change, before: String, after: String, file: String) throws {
    let old = try parseMatches(yaml: before, file: file)
    var expected = old.map(Content.init)
    let actual = try parseMatches(yaml: after, file: file).map(Content.init)
    // The changed snippet must have exactly the draft's shortcut, name, text and questions. Its variable list
    // may gain the date, clipboard or form entries the text needs; dedicated tests check those.
    switch change {
    case .add(let draft, _):
        expected.append(Content(draft))
        if let added = actual.last { expected[expected.count - 1].variables = added.variables }
    case .update(let index, let draft):
        expected[index].apply(draft)
        if actual.indices.contains(index) {
            expected[index].variables = actual[index].variables
            // Questions the editor can't change follow the text (Espanso's `form:` shorthand).
            if !old[index].questionsEditable { expected[index].questions = actual[index].questions }
        }
    case .delete(let index):
        expected.remove(at: index)
    }
    guard actual == expected else { throw EditError.wouldAlterOtherSnippets }
}

struct Content: Equatable {
    var triggers: [String]
    var label: String?
    var text: String
    var questions: [Question]
    var variables: [String: String]

    init(_ s: Snippet) {
        triggers = s.triggers
        label = s.label
        text = s.text
        questions = s.questions
        variables = s.variables
    }

    init(_ draft: Draft) {
        triggers = []
        text = ""
        questions = []
        variables = [:]
        apply(draft)
    }

    mutating func apply(_ draft: Draft) {
        triggers = [draft.trigger.trimmingCharacters(in: .whitespaces)] + triggers.dropFirst()
        label = draft.label.isEmpty ? nil : draft.label
        text = draft.text
        questions = draft.questions
    }
}
