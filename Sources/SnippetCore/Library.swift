import Foundation
import Yams

/// A fill-in question a snippet asks when it expands (a form field, choice or list).
public struct Question: Equatable, Sendable {
    public let name: String
    /// "text", "multi-line text", "choice" or "list".
    public let kind: String
    public let options: [String]
    /// What the pop-up form shows next to the answer box, e.g. "Opposing counsel".
    public let prompt: String

    public init(name: String, kind: String, options: [String] = [], prompt: String? = nil) {
        self.name = name
        self.kind = kind
        self.options = options
        self.prompt = prompt ?? name
    }
}

public struct Snippet: Identifiable, Sendable {
    public let id: String
    public let file: String
    /// Position in the file's `matches` list.
    public let index: Int
    public let triggers: [String]
    public let label: String?
    public let text: String
    public let questions: [Question]
    /// Variable name -> Espanso type (date, form, shell, clipboard, ...).
    public let variables: [String: String]
    /// Date variable name -> its strftime format, e.g. "%B %-d, %Y".
    public let dateFormats: [String: String]
    /// The name of the snippet's form variable, used in `{{form1.field}}`.
    public let formName: String?
    /// False when questions come from more than one place (two forms, a separate choice list,
    /// Espanso's `form:` shorthand); the editor then leaves them as they are.
    public let questionsEditable: Bool

    /// Lives in a subfolder of the match folder, such as an installed Espanso package; shown but never edited.
    public var inSubfolder: Bool { file.contains("/") }

    public var title: String { label ?? triggers.first ?? "Untitled" }
    public var runsCommand: Bool { variables.values.contains { $0 == "shell" || $0 == "script" } }
    public var searchText: String { ([title, text] + triggers).joined(separator: " ") }
}

public enum LibraryError: LocalizedError {
    case notAMatchFile(String)
    public var errorDescription: String? {
        switch self { case .notAMatchFile(let f): "\(f).yml is not an Espanso match file." }
    }
}

/// `SNIPPET_STUDIO_DEMO=<folder>` runs the app on a sample library (its `match/` folder) with its own colors and
/// backups, leaving the real Espanso files and settings untouched. Used for screenshots and for trying the app out.
let demoFolder = ProcessInfo.processInfo.environment["SNIPPET_STUDIO_DEMO"].map { URL(filePath: $0, directoryHint: .isDirectory) }

public let espansoMatchFolder = demoFolder?.appending(path: "match")
    ?? URL.homeDirectory.appending(path: "Library/Application Support/espanso/match")

/// Reads every match file under the folder, subfolders included (Espanso loads those too, e.g. installed
/// packages). A file that can't be read is reported in `problems` and skipped, so one odd file doesn't hide the rest.
public func loadLibrary(from folder: URL = espansoMatchFolder) throws -> (snippets: [Snippet], problems: [String]) {
    var snippets: [Snippet] = []
    var problems: [String] = []
    for (url, name) in try matchFiles(in: folder) {
        do {
            snippets += try parseMatches(yaml: String(contentsOf: url, encoding: .utf8), file: name)
        } catch {
            problems.append("\(name).yml: " + ((error as? LocalizedError)?.errorDescription ?? "\(error)"))
        }
    }
    return (snippets, problems)
}

/// The `.yml` files under a folder with their names relative to the match folder ("base", "packages/x/package").
func matchFiles(in folder: URL, prefix: String = "") throws -> [(url: URL, name: String)] {
    try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles)
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
        .flatMap { url -> [(url: URL, name: String)] in
            let name = url.lastPathComponent
            if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                return try matchFiles(in: url, prefix: prefix + name + "/")
            }
            // Espanso skips files whose names start with an underscore.
            return url.pathExtension == "yml" && !name.hasPrefix("_")
                ? [(url, prefix + url.deletingPathExtension().lastPathComponent)] : []
        }
}

public func parseMatches(yaml: String, file: String) throws -> [Snippet] {
    guard let node = try Yams.compose(yaml: yaml) else { return [] } // an empty file has no snippets yet
    guard let root = plainValue(node) as? [String: Any] else { throw LibraryError.notAMatchFile(file) }
    let matches = root["matches"] as? [[String: Any]] ?? []
    // Dates shared by the whole file (`global_vars`), so the preview uses their format too.
    var globalFormats: [String: String] = [:]
    for variable in root["global_vars"] as? [[String: Any]] ?? [] where variable["type"] as? String == "date" {
        globalFormats[variable["name"] as? String ?? ""] = (variable["params"] as? [String: Any])?["format"] as? String
    }
    return matches.enumerated().map { index, match in
        var types: [String: String] = [:]
        var formats = globalFormats
        var questions: [Question] = []
        for variable in match["vars"] as? [[String: Any]] ?? [] {
            let name = variable["name"] as? String ?? ""
            let type = variable["type"] as? String ?? ""
            let params = variable["params"] as? [String: Any] ?? [:]
            types[name] = type
            switch type {
            case "date":
                formats[name] = params["format"] as? String
            case "form":
                questions += formQuestions(layout: params["layout"] as? String ?? "",
                                           fields: params["fields"] as? [String: Any] ?? [:])
            case "choice", "list":
                questions.append(Question(name: name, kind: type, options: values(params["values"])))
            default: break
            }
        }
        // Espanso's shorthand: `form:` + `form_fields:` instead of a form variable.
        if let form = match["form"] as? String {
            questions += formQuestions(layout: form, fields: match["form_fields"] as? [String: Any] ?? [:])
        }
        let triggers = match["triggers"] as? [String] ?? [match["trigger"] as? String].compactMap { $0 }
        let text = match["replace"] as? String ?? match["form"] as? String
            ?? match["markdown"] as? String ?? match["html"] as? String ?? ""
        let forms = types.filter { $0.value == "form" }.map(\.key)
        let editable = forms.count <= 1 && match["form"] == nil
            && !types.values.contains { $0 == "choice" || $0 == "list" }
        return Snippet(id: "\(file)#\(index)", file: file, index: index, triggers: triggers,
                       label: match["label"] as? String, text: text,
                       questions: questions, variables: types, dateFormats: formats,
                       formName: forms.first, questionsEditable: editable)
    }
}

func formQuestions(layout: String, fields: [String: Any]) -> [Question] {
    var previousEnd = layout.startIndex
    return layout.matches(of: /\[\[\s*(\w+)\s*\]\]/).map { match in
        // The prompt is the text just before the field on the same line: "Opposing counsel [[counsel]]".
        let before = String(layout[previousEnd..<match.range.lowerBound])
        previousEnd = match.range.upperBound
        let prompt = (before.components(separatedBy: "\n").last ?? "").trimmingCharacters(in: .whitespaces)
        let name = String(match.1)
        let spec = fields[name] as? [String: Any] ?? [:]
        let type = spec["type"] as? String ?? "text"
        let multiline = ["true", "True", "TRUE"].contains(spec["multiline"] as? String ?? "")
        return Question(name: name, kind: type == "text" && multiline ? "multi-line text" : type,
                        options: values(spec["values"]), prompt: prompt.isEmpty ? nil : prompt)
    }
}

/// The document as plain Swift values, with every value as text and never a number, date or other type.
/// Yams's own converter traps (an uncatchable crash) on some input a package file could hold: a `!!int`
/// base-60 value that overflows, or a mapping key that is itself a list. Keys that aren't text are skipped.
func plainValue(_ node: Node) -> Any {
    switch node {
    case .scalar(let scalar):
        // A bare `~`, `null` or nothing means "no value", as Espanso reads it.
        if scalar.style == .plain && ["", "~", "null", "Null", "NULL"].contains(scalar.string) { return NSNull() }
        return scalar.string
    case .sequence(let sequence):
        return sequence.map(plainValue)
    case .mapping(let mapping):
        var dictionary: [String: Any] = [:]
        for (keyNode, value) in mapping {
            guard let key = keyNode.scalar?.string, dictionary[key] == nil else { continue }
            dictionary[key] = plainValue(value)
        }
        return dictionary
    default:
        return NSNull()
    }
}

/// Espanso accepts choice values as a YAML list or as one value per line.
func values(_ raw: Any?) -> [String] {
    if let list = raw as? [Any] { return list.map { "\($0)" } }
    return (raw as? String)?.split(separator: "\n")
        .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } ?? []
}

public enum Segment: Equatable, Sendable {
    case text(String)
    case token(name: String, isQuestion: Bool)
}

/// Splits snippet text into plain text and `{{variable}}` / `[[field]]` tokens.
public func segments(_ text: String) -> [Segment] {
    var out: [Segment] = []
    var rest = text[...]
    while let match = rest.firstMatch(of: /\{\{\s*([\w.]+)\s*\}\}|\[\[\s*(\w+)\s*\]\]/) {
        if match.range.lowerBound > rest.startIndex {
            out.append(.text(String(rest[..<match.range.lowerBound])))
        }
        if let field = match.2 {
            out.append(.token(name: String(field), isQuestion: true))
        } else if let variable = match.1 {
            // `{{form1.counsel}}` is a form answer; `{{today}}` is a plain variable.
            out.append(.token(name: String(variable), isQuestion: variable.contains(".")))
        }
        rest = rest[match.range.upperBound...]
    }
    if !rest.isEmpty { out.append(.text(String(rest))) }
    return out
}
