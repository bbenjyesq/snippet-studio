import SnippetCore
import SwiftUI

/// Step-by-step builder for a new snippet (the Gallery design's right-hand panel, as a sheet).
struct SnippetBuilder: View {
    let library: [Snippet]
    /// Saves the draft; returns why it failed, if it did. Shown here because an alert can't appear over a sheet.
    let onSave: (Draft) -> String?
    @Environment(\.dismiss) private var dismiss
    @State private var step = 1
    @State private var draft: Draft
    @State private var saveError: String?

    /// `start` is blank for a new snippet, or a copy's name and text when duplicating.
    init(library: [Snippet], start: Draft, onSave: @escaping (Draft) -> String?) {
        self.library = library
        self.onSave = onSave
        _draft = State(initialValue: start)
    }

    /// Step 2 only checks the shortcut; the text is filled in on step 3.
    private var shortcutProblem: String? {
        var check = draft
        check.text = "x"
        return validationProblem(check, in: library)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Snippet builder").font(.title2.bold())
                Spacer()
                Text(verbatim: "Step \(step) of 3").foregroundStyle(.secondary)
            }
            ProgressView(value: Double(step), total: 3)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    switch step {
                    case 1:
                        Text("Name it").font(.headline)
                        TextField("For example: Meet and confer letter", text: $draft.label)
                            .textFieldStyle(.roundedBorder)
                        Text("A plain-English name you’ll recognize later. Optional.")
                            .font(.callout).foregroundStyle(.secondary)
                    case 2:
                        Text("The shortcut you’ll type").font(.headline)
                        TextField("For example: ;mcl", text: $draft.trigger)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                        Text("Type the whole shortcut yourself, including the ; if you want one. A leading ; keeps it from firing by accident while you type normally.")
                            .font(.callout).foregroundStyle(.secondary)
                        if let shortcutProblem, !draft.trigger.trimmingCharacters(in: .whitespaces).isEmpty {
                            Label(shortcutProblem, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                        }
                    default:
                        Text("What it types").font(.headline)
                        Composer(draft: $draft, snippet: nil)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let saveError { Label(saveError, systemImage: "exclamationmark.triangle").foregroundStyle(.red) }
            HStack {
                Button("Cancel", role: .cancel) { dismiss() }
                Spacer()
                if step > 1 { Button("Back") { step -= 1 } }
                if step < 3 {
                    Button("Next") { step += 1 }
                        .keyboardShortcut(.defaultAction)
                        .disabled(step == 2 && shortcutProblem != nil)
                } else {
                    Button("Save snippet") {
                        saveError = onSave(draft)
                        if saveError == nil { dismiss() }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(validationProblem(draft, in: library) != nil)
                }
            }
        }
        .padding(24)
        .frame(width: 640, height: 680)
    }
}

/// The fields for changing an existing snippet, shown in the side panel.
struct SnippetEditor: View {
    let snippet: Snippet
    let library: [Snippet]
    let onSave: (Draft) -> Bool
    let onCancel: () -> Void
    @State private var draft: Draft

    init(snippet: Snippet, library: [Snippet], onSave: @escaping (Draft) -> Bool, onCancel: @escaping () -> Void) {
        self.snippet = snippet
        self.library = library
        self.onSave = onSave
        self.onCancel = onCancel
        _draft = State(initialValue: Draft(snippet))
    }

    private var problem: String? { validationProblem(draft, in: library, editing: snippet.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Name").font(.headline)
            TextField("Name", text: $draft.label).textFieldStyle(.roundedBorder)
            Text("Shortcut").font(.headline)
            TextField("Shortcut", text: $draft.trigger)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
            if snippet.triggers.count > 1 {
                Text(verbatim: "Also triggered by: \(snippet.triggers.dropFirst().joined(separator: ", ")) (unchanged)")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Text("What it types").font(.headline)
            Composer(draft: $draft, snippet: snippet)
            if let problem { Label(problem, systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
            HStack {
                Button("Cancel", role: .cancel, action: onCancel)
                Spacer()
                Button("Save") { _ = onSave(draft) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(problem != nil || draft == Draft(snippet))
            }
            Text("A backup is saved automatically before every change. Notes after # at the end of one of this snippet’s lines are not kept; notes on their own line are.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }
}

/// The text with Insert buttons, the questions it will ask, and a live "Try it" preview.
struct Composer: View {
    @Binding var draft: Draft
    /// The saved snippet, for its existing date formats and variables; nil while building a new one.
    let snippet: Snippet?
    @State private var selection: TextSelection?
    @State private var addingQuestion = false
    @State private var answers: [String: String] = [:]

    private var questionsEditable: Bool { snippet?.questionsEditable ?? true }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text("Insert:").foregroundStyle(.secondary)
                Button("Today’s date") { insert("{{date}}") }
                Button("Clipboard") { insert("{{clipboard}}") }
                Button("Question…") { addingQuestion = true }
                    .disabled(!questionsEditable)
                    .popover(isPresented: $addingQuestion) {
                        QuestionForm { prompt, kind, options in
                            insert(draft.addQuestion(prompt: prompt, kind: kind, options: options))
                        }
                    }
                Button("Cursor lands here") { insert("$|$") }
            }
            .controlSize(.small)

            TextEditor(text: $draft.text, selection: $selection)
                .font(.system(.body, design: .serif))
                .frame(minHeight: 140)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.secondary.opacity(0.4)))

            if !draft.questions.isEmpty {
                Text("Questions it will ask").font(.headline)
                ForEach(draft.questions, id: \.name) { question in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(question.prompt).bold()
                            Text(questionSummary(question)).font(.callout).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if questionsEditable {
                            Button("Remove question", systemImage: "trash") { draft.removeQuestion(named: question.name) }
                                .labelStyle(.iconOnly)
                                .buttonStyle(.borderless)
                        }
                    }
                }
                Text(verbatim: questionsEditable
                     ? "Adding or removing a question changes only that question in the pop-up form."
                     : "These questions are set up in a way the editor can’t change yet.")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            GroupBox("Try it") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(draft.questions, id: \.name) { question in
                        answerField(question)
                    }
                    Text(preview(draft.text, variables: snippet?.variables ?? [:],
                                 dateFormats: snippet?.dateFormats ?? [:], answers: answers))
                        .font(.system(.body, design: .serif))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    @ViewBuilder private func answerField(_ question: Question) -> some View {
        let answer = Binding(get: { answers[question.name] ?? "" }, set: { answers[question.name] = $0 })
        if question.options.isEmpty {
            TextField(question.prompt, text: answer).textFieldStyle(.roundedBorder)
        } else {
            Picker(question.prompt, selection: answer) {
                Text("Choose…").tag("")
                ForEach(question.options, id: \.self) { Text($0).tag($0) }
            }
        }
    }

    /// Puts a fill-in where the cursor is (or at the end) and leaves the cursor just after it.
    private func insert(_ token: String) {
        guard case .some(.selection(let range)) = selection?.indices, range.upperBound <= draft.text.endIndex else {
            draft.text += token
            return
        }
        let offset = draft.text.distance(from: draft.text.startIndex, to: range.lowerBound) + token.count
        draft.text.replaceSubrange(range, with: token)
        selection = TextSelection(insertionPoint: draft.text.index(draft.text.startIndex, offsetBy: offset))
    }
}

/// Small pop-up for adding one question to the snippet's form.
struct QuestionForm: View {
    let onAdd: (_ prompt: String, _ kind: String, _ options: [String]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var prompt = ""
    @State private var kind = "text"
    @State private var choices = ""

    private var options: [String] {
        choices.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("New question").font(.headline)
            TextField("What should it ask? For example: Opposing counsel", text: $prompt)
                .textFieldStyle(.roundedBorder)
            Picker("Answer", selection: $kind) {
                Text("Short answer").tag("text")
                Text("Long answer").tag("multi-line text")
                Text("Pick one from a list").tag("choice")
            }
            if kind == "choice" {
                Text("Choices, one per line").font(.callout)
                TextEditor(text: $choices)
                    .frame(height: 90)
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.secondary.opacity(0.4)))
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Add question") {
                    onAdd(prompt, kind, kind == "choice" ? options : [])
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(prompt.trimmingCharacters(in: .whitespaces).isEmpty || (kind == "choice" && options.isEmpty))
            }
        }
        .padding(16)
        .frame(width: 360)
    }
}

/// "Short answer", "Long answer" or "Pick one: A · B", for the questions lists.
func questionSummary(_ question: Question) -> String {
    switch question.kind {
    case "choice", "list": "Pick one: " + question.options.joined(separator: " · ")
    case "multi-line text": "Long answer"
    default: "Short answer"
    }
}

struct RestoreSheet: View {
    let onRestore: (Backup) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var backups = listBackups()
    @State private var chosen: Backup?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Restore a backup").font(.title2.bold())
            Text("A backup is saved before every change (the newest 200 are kept). Restoring also backs up the current version first, so it can be undone.")
                .foregroundStyle(.secondary)
            if backups.isEmpty {
                Text("No backups yet. They appear after your first save.").padding(.vertical)
            }
            List(backups) { backup in
                HStack {
                    VStack(alignment: .leading) {
                        Text(verbatim: "\(backup.file).yml")
                        Text(backup.date.formatted(date: .abbreviated, time: .standard))
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Restore…") { chosen = backup }
                }
            }
            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 520, height: 440)
        .confirmationDialog(Text("Replace your current snippets with this backup?"),
                            isPresented: Binding(get: { chosen != nil }, set: { if !$0 { chosen = nil } }),
                            presenting: chosen) { backup in
            Button("Restore", role: .destructive) {
                onRestore(backup)
                dismiss()
            }
        }
    }
}
