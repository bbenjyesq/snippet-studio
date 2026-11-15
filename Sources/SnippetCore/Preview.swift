import Foundation

/// What the snippet will type, with sample answers filled in. Never runs commands or reads the clipboard:
/// those show as `[name]` placeholders.
public func preview(_ text: String, variables: [String: String], dateFormats: [String: String],
                    answers: [String: String], now: Date = .now, timeZone: TimeZone = .current) -> String {
    segments(text.replacing("$|$", with: "")).map { segment in
        switch segment {
        case .text(let text):
            return text
        case .token(let name, true):
            let field = name.split(separator: ".").last.map(String.init) ?? name
            return answers[field].flatMap { $0.isEmpty ? nil : $0 } ?? "[\(field)]"
        case .token(let name, false):
            // `{{date}}` from the Insert button may not be saved yet, so it has no entry in `variables`.
            let type = variables[name] ?? (name == "date" || dateFormats[name] != nil ? "date" : "")
            guard type == "date" else { return "[\(name)]" }
            return formatDate(now, strftime: dateFormats[name] ?? defaultDateFormat, timeZone: timeZone)
        }
    }.joined()
}

/// Formats a date with an Espanso (strftime) pattern such as "%B %-d, %Y".
func formatDate(_ date: Date, strftime: String, timeZone: TimeZone) -> String {
    let codes: [Character: String] = [
        "Y": "yyyy", "y": "yy", "m": "MM", "d": "dd", "B": "MMMM", "b": "MMM",
        "A": "EEEE", "a": "EEE", "H": "HH", "I": "hh", "M": "mm", "S": "ss", "p": "a",
    ]
    let unpadded: [Character: String] = ["m": "M", "d": "d", "H": "H", "I": "h", "M": "m", "S": "s"]
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US")
    formatter.timeZone = timeZone
    func part(_ pattern: String) -> String {
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }
    var out = ""
    var characters = strftime.makeIterator()
    while let c = characters.next() {
        guard c == "%", var code = characters.next() else { out.append(c); continue }
        let noPadding = code == "-"
        if noPadding { code = characters.next() ?? code }
        if code == "e" { // day padded with a space, as Espanso types it: " 5"
            let day = part("d")
            out += (noPadding ? "" : String(repeating: " ", count: 2 - day.count)) + day
        } else if let pattern = noPadding ? unpadded[code] ?? codes[code] : codes[code] {
            out += part(pattern)
        } else {
            out += code == "%" ? "%" : "%\(code)" // unknown code: show it as written
        }
    }
    return out
}
