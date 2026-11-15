import AppKit
import SnippetCore
import SwiftUI

@main
struct SnippetStudioApp: App {
    @AppStorage("viewMode") private var mode: ViewMode = .gallery
    @FocusedValue(\.isEditingSnippet) private var isEditing

    init() {
        // shortcut: `swift run` starts a bare executable, so make it a normal Dock app; drop once packaged as a .app.
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        // One window only: a second one would hold its own copy of the colors and could save over the first's.
        Window("Snippet Studio", id: "main") {
            LibraryView()
                .frame(minWidth: 900, minHeight: 600)
                .onAppear { NSApplication.shared.activate() }
        }
        .defaultSize(width: 1280, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {} // one library window; ⌘N is New Snippet
            CommandGroup(after: .toolbar) {
                ForEach(Array(ViewMode.allCases.enumerated()), id: \.element) { index, mode in
                    Button("\(mode.title) View") { self.mode = mode }
                        .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")))
                        .disabled(isEditing == true) // switching views would discard an unsaved edit
                }
            }
        }
    }
}

struct EditingSnippetKey: FocusedValueKey { typealias Value = Bool }

extension FocusedValues {
    /// True while a snippet's edit form is open, so the View menu can't switch away from unsaved text.
    var isEditingSnippet: Bool? {
        get { self[EditingSnippetKey.self] }
        set { self[EditingSnippetKey.self] = newValue }
    }
}

enum ViewMode: String, CaseIterable, Identifiable {
    case gallery, counsel, docket
    var id: Self { self }
    var title: String { rawValue.capitalized }
}

/// What the sidebar can show.
enum SidebarItem: Hashable {
    case all, recent, noGroup
    case group(UUID)
    case file(String)
}

struct LibraryView: View {
    @AppStorage("viewMode") private var mode: ViewMode = .gallery
    @State private var snippets: [Snippet] = []
    @State private var look = loadAppearance()
    @State private var loadError: String?
    @State private var query = ""
    @State private var filter: SidebarItem? = .all
    @State private var selectedID: Snippet.ID?
    @State private var editingID: Snippet.ID?
    @State private var showBuilder = false
    @State private var builderStart = Draft(trigger: "", label: "", text: "")
    @State private var duplicateOf: Snippet?
    @State private var showRestore = false
    @State private var groupSheet: SnippetGroup?
    @State private var groupSheetFor: Snippet?
    @State private var deleting: Snippet?
    @State private var alertMessage: String?
    @State private var savedNote: String?
    @FocusState private var searchFocused: Bool
    @State private var docketOrder = [KeyPathComparator(\DocketRow.group)]

    private var files: [String] { Array(Set(snippets.map(\.file))).sorted() }
    private var editableFiles: [String] { files.filter { !$0.contains("/") } } // subfolders hold packages
    private var shown: [Snippet] {
        let list = snippets.filter {
            matches($0, filter ?? .all) && (query.isEmpty || $0.searchText.localizedCaseInsensitiveContains(query))
        }
        return filter == .recent ? list.sorted { edited($0) > edited($1) } : list
    }
    private var selected: Snippet? { snippets.first { $0.id == selectedID } }

    private func edited(_ snippet: Snippet) -> Date { look.editedAt[appearanceKey(snippet)] ?? .distantPast }
    private func colorName(_ snippet: Snippet) -> String { look.group(of: snippet)?.color ?? "gray" }
    private func icon(_ snippet: Snippet) -> String { look.icon(of: snippet) ?? defaultIcon }
    private func canEdit(_ snippet: Snippet) -> Bool { canDelete(snippet) && !snippet.triggers.isEmpty }
    private func canDelete(_ snippet: Snippet) -> Bool { !snippet.runsCommand && !snippet.inSubfolder }

    private func matches(_ snippet: Snippet, _ item: SidebarItem) -> Bool {
        switch item {
        case .all: true
        case .recent: edited(snippet) > Date.now.addingTimeInterval(-30 * 86_400)
        case .noGroup: look.group(of: snippet) == nil
        case .group(let id): look.group(of: snippet)?.id == id
        case .file(let name): snippet.file == name
        }
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            content
        }
        .searchable(text: $query, placement: .toolbar, prompt: "Search snippets")
        .searchFocused($searchFocused)
        .background {
            // shortcut: an invisible button gives ⌘F to the search field; swap for a menu command if one is ever added.
            Button("Find") { searchFocused = true }
                .keyboardShortcut("f")
                .opacity(0)
                .accessibilityHidden(true)
        }
        .toolbar {
            Picker("View", selection: $mode) {
                ForEach(ViewMode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .disabled(editingID != nil)
            .help(editingID != nil ? "Save or cancel the edit to switch views" : "Gallery, Counsel or Docket")
            Button("Restore a Backup…", systemImage: "clock.arrow.circlepath") { showRestore = true }
            Button("Reload", systemImage: "arrow.clockwise", action: reload)
                .keyboardShortcut("r")
                .help("Reload (⌘R)")
            Button("New Snippet", systemImage: "plus") {
                builderStart = Draft(trigger: "", label: "", text: "")
                duplicateOf = nil
                showBuilder = true
            }
            .keyboardShortcut("n")
            .help("New Snippet (⌘N)")
            .buttonStyle(.borderedProminent)
        }
        .sheet(isPresented: $showBuilder) {
            SnippetBuilder(library: snippets, start: builderStart, onSave: { add($0) })
        }
        .sheet(isPresented: $showRestore) {
            RestoreSheet { backup in
                do {
                    try restore(backup)
                    selectedID = nil
                    reload()
                } catch {
                    alertMessage = error.localizedDescription
                }
            }
        }
        .sheet(item: $groupSheet) { group in
            GroupSheet(group: group, isNew: !look.groups.contains { $0.id == group.id }) { saved in
                let snippet = groupSheetFor
                updateLook { look in
                    if let index = look.groups.firstIndex(where: { $0.id == saved.id }) {
                        look.groups[index] = saved
                    } else {
                        look.groups.append(saved)
                    }
                    if let snippet { look.groupOf[appearanceKey(snippet)] = saved.id }
                }
                groupSheetFor = nil
            }
        }
        .confirmationDialog(Text(verbatim: "Delete “\(deleting?.title ?? "")”?"),
                            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            presenting: deleting) { snippet in
            Button("Delete", role: .destructive) { delete(snippet) }
        } message: { _ in
            Text("A backup is saved first, so you can bring it back with Restore a Backup….")
        }
        .alert("Nothing was changed",
               isPresented: Binding(get: { alertMessage != nil }, set: { if !$0 { alertMessage = nil } })) {
            Button("OK") {}
        } message: {
            Text(alertMessage ?? "")
        }
        .onAppear(perform: reload)
        .focusedSceneValue(\.isEditingSnippet, editingID != nil)
        .onChange(of: selectedID) { _, new in
            if editingID != new { editingID = nil } // an open edit form closes when another snippet is chosen
        }
        .overlay(alignment: .bottom) {
            if let savedNote {
                Label(savedNote, systemImage: "checkmark.circle.fill")
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                    .padding(20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: savedNote)
    }

    // MARK: Sidebar

    private var sidebar: some View {
        List(selection: $filter) {
            Section("Library") {
                sidebarRow("All Snippets", symbol: "square.stack.fill", color: "blue", item: .all)
                sidebarRow("Recently Edited", symbol: "clock.fill", color: "gray", item: .recent)
            }
            Section("Groups") {
                ForEach(look.groups) { group in
                    sidebarRow(group.name, symbol: "folder.fill", color: group.color, item: .group(group.id))
                        .contextMenu {
                            Button("Edit Group…") {
                                groupSheetFor = nil
                                groupSheet = group
                            }
                            Button("Delete Group (keeps its snippets)", role: .destructive) {
                                if filter == .group(group.id) { filter = .all }
                                updateLook { $0.deleteGroup(group.id) }
                            }
                        }
                }
                sidebarRow("No Group", symbol: "tray.fill", color: "gray", item: .noGroup)
                Button {
                    groupSheetFor = nil
                    groupSheet = SnippetGroup(name: "", color: "blue")
                } label: {
                    Label("New Group…", systemImage: "plus")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }
            Section("Espanso Files") {
                ForEach(files, id: \.self) { name in
                    Label(name + ".yml", systemImage: "doc")
                        .badge(snippets.filter { $0.file == name }.count)
                        .tag(SidebarItem.file(name))
                }
            }
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 230)
    }

    private func sidebarRow(_ title: String, symbol: String, color: String, item: SidebarItem) -> some View {
        Label { Text(verbatim: title) } icon: { Badge(symbol: symbol, color: color) }
            .badge(snippets.filter { matches($0, item) }.count)
            .tag(item)
    }

    private var heading: String {
        switch filter ?? .all {
        case .all: "All Snippets"
        case .recent: "Recently Edited"
        case .noGroup: "No Group"
        case .group(let id): look.groups.first(where: { $0.id == id })?.name ?? "Group"
        case .file(let name): name + ".yml"
        }
    }

    // MARK: The three views share one library, one search and one editor panel; only the arrangement differs.

    @ViewBuilder private var content: some View {
        switch mode {
        case .gallery:
            HStack(spacing: 0) { gallery; sidePanel }
        case .counsel:
            HStack(spacing: 0) { snippetList; sidePanel }
        case .docket:
            VStack(spacing: 0) { docketTable; bottomPanel }
        }
    }

    @ViewBuilder private var sidePanel: some View {
        if let snippet = selected {
            Divider()
            detail(snippet, showFile: false).frame(width: 400)
        }
    }

    @ViewBuilder private var bottomPanel: some View {
        if let snippet = selected {
            Divider()
            detail(snippet, showFile: true).frame(height: 320)
        }
    }

    private func detail(_ snippet: Snippet, showFile: Bool) -> some View {
        SnippetDetail(
            snippet: snippet, library: snippets, showFile: showFile,
            isEditing: Binding(get: { editingID == snippet.id }, set: { editingID = $0 ? snippet.id : nil }),
            groups: look.groups,
            group: groupBinding(snippet),
            icon: Binding(get: { look.icon(of: snippet) }, set: { icon in updateLook { $0.iconOf[appearanceKey(snippet)] = icon } }),
            colorName: colorName(snippet),
            onSave: { draft in
                guard succeeded(perform(.update(index: snippet.index, draft), in: snippet.file, shown: snippet)) else { return false }
                let newKey = snippets.first(where: { $0.id == snippet.id }).map(appearanceKey) ?? draft.trigger
                updateLook { look in
                    look.move(from: appearanceKey(snippet), to: newKey)
                    look.editedAt[newKey] = .now
                }
                return true
            },
            onDelete: { deleting = snippet })
            // A different snippet, or the same position with new content after a Reload, starts with a fresh panel
            // so an open Edit form can never be saved over the wrong snippet.
            .id("\(snippet.id)|\(snippet.searchText)")
    }

    private func groupBinding(_ snippet: Snippet) -> Binding<UUID?> {
        Binding(get: { look.group(of: snippet)?.id },
                set: { id in updateLook { $0.groupOf[appearanceKey(snippet)] = id } })
    }

    @ViewBuilder private var errorLabel: some View {
        if let loadError { Label(loadError, systemImage: "exclamationmark.triangle").foregroundStyle(.red) }
    }

    /// Right-click menu for a snippet, the same in every view.
    @ViewBuilder private func snippetMenu(_ snippet: Snippet) -> some View {
        Button("Edit Snippet…") {
            selectedID = snippet.id
            editingID = snippet.id
        }
        .disabled(!canEdit(snippet))
        Button("Duplicate") { duplicate(snippet) }.disabled(!canEdit(snippet))
        Divider()
        Picker("Group", selection: groupBinding(snippet)) {
            ForEach(look.groups) { group in
                Label { Text(verbatim: group.name) } icon: {
                    Image(systemName: "circle.fill").foregroundStyle(groupColor(group.color))
                }
                .tag(Optional(group.id))
            }
            Text("No Group").tag(UUID?.none)
        }
        Button("New Group…") {
            groupSheetFor = snippet
            groupSheet = SnippetGroup(name: "", color: "blue")
        }
        Menu("Icon") {
            ForEach(snippetIcons, id: \.symbol) { option in
                Button(option.name, systemImage: option.symbol) {
                    updateLook { $0.iconOf[appearanceKey(snippet)] = option.symbol }
                }
            }
        }
        Divider()
        Button("Delete…", role: .destructive) { deleting = snippet }.disabled(!canDelete(snippet))
    }

    // MARK: Gallery: colored tiles, in sections by group

    private struct TileSection {
        let title: String
        let color: String
        let snippets: [Snippet]
    }

    private var sections: [TileSection] {
        guard filter == .all, !look.groups.isEmpty else { return [TileSection(title: "", color: "gray", snippets: shown)] }
        let grouped = look.groups.map { group in
            TileSection(title: group.name, color: group.color, snippets: shown.filter { look.group(of: $0)?.id == group.id })
        }
        let loose = TileSection(title: "No Group", color: "gray", snippets: shown.filter { look.group(of: $0) == nil })
        return (grouped + [loose]).filter { !$0.snippets.isEmpty }
    }

    private var gallery: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: heading).font(.largeTitle.bold())
                    Text(verbatim: "\(shown.count) snippet\(shown.count == 1 ? "" : "s")").foregroundStyle(.secondary)
                }
                errorLabel
                ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                    if !section.title.isEmpty {
                        HStack(spacing: 8) {
                            Circle().fill(groupColor(section.color)).frame(width: 10, height: 10)
                            Text(verbatim: section.title).font(.title3.weight(.semibold))
                            Text(verbatim: "\(section.snippets.count)").foregroundStyle(.secondary)
                        }
                        .padding(.top, 14)
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 14)], spacing: 14) {
                        ForEach(section.snippets) { snippet in
                            Button { selectedID = snippet.id } label: {
                                SnippetTile(snippet: snippet, color: colorName(snippet), icon: icon(snippet),
                                            isSelected: snippet.id == selectedID)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text(verbatim: "\(snippet.title), \(snippet.triggers.first ?? "pattern"), "
                                                     + (look.group(of: snippet)?.name ?? "No Group")))
                            .contextMenu { snippetMenu(snippet) }
                        }
                    }
                }
                if shown.isEmpty {
                    if query.isEmpty {
                        ContentUnavailableView("Nothing here yet", systemImage: "square.stack")
                    } else {
                        ContentUnavailableView.search(text: query)
                    }
                }
            }
            .padding(28)
        }
    }

    // MARK: Counsel: sidebar, list, editor

    private var snippetList: some View {
        VStack(alignment: .leading, spacing: 0) {
            errorLabel.padding(8)
            List(shown, selection: $selectedID) { snippet in
                HStack(spacing: 10) {
                    Badge(symbol: icon(snippet), color: colorName(snippet), size: 26)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(verbatim: snippet.title).fontWeight(.medium)
                        Text(verbatim: snippet.triggers.joined(separator: " "))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
                .contextMenu { snippetMenu(snippet) }
            }
        }
        .frame(width: 320)
        .navigationTitle(heading)
    }

    // MARK: Docket: table with the Espanso file under it

    struct DocketRow: Identifiable {
        let snippet: Snippet
        let shortcut: String
        let group: String
        let color: String
        var id: Snippet.ID { snippet.id }
        var name: String { snippet.title }
        var file: String { snippet.file + ".yml" }
        var questions: Int { snippet.questions.count }
    }

    private var docketTable: some View {
        let rows = shown.map { snippet in
            DocketRow(snippet: snippet, shortcut: snippet.triggers.joined(separator: " "),
                      group: look.group(of: snippet)?.name ?? "No Group", color: colorName(snippet))
        }
        return VStack(alignment: .leading, spacing: 8) {
            errorLabel
            Table(rows.sorted(using: docketOrder), selection: $selectedID, sortOrder: $docketOrder) {
                TableColumn("Shortcut", value: \.shortcut) { row in
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 2).fill(groupColor(row.color)).frame(width: 4, height: 16)
                        Text(verbatim: row.shortcut).font(.system(.body, design: .monospaced))
                    }
                }
                TableColumn("Name", value: \.name)
                TableColumn("Group", value: \.group) { row in
                    HStack(spacing: 6) {
                        Circle().fill(groupColor(row.color)).frame(width: 8, height: 8)
                        Text(verbatim: row.group)
                    }
                }
                TableColumn("File", value: \.file)
                TableColumn("Questions", value: \.questions) { row in Text(verbatim: "\(row.questions)") }
            }
            .contextMenu(forSelectionType: Snippet.ID.self) { ids in
                if let id = ids.first, let snippet = snippets.first(where: { $0.id == id }) { snippetMenu(snippet) }
            }
            .frame(minHeight: 180)
        }
        .padding([.horizontal, .top], 12)
        .navigationTitle(heading)
    }

    // MARK: Saving

    /// Saves a change (with an automatic backup) and refreshes the library. Returns why it failed, if it did.
    private func perform(_ change: Change, in file: String, shown: Snippet? = nil) -> String? {
        do {
            try save(change, file: file, shown: shown)
            reload()
            confirm("Saved to Espanso")
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// Shows a failure as an alert; returns whether the save worked.
    private func succeeded(_ error: String?) -> Bool {
        alertMessage = error
        return error == nil
    }

    /// Adds a new snippet to the file shown in the sidebar (or the first one), in the group shown or the copied one's.
    /// A copy goes in its original's file, built from the original's own settings.
    private func add(_ draft: Draft) -> String? {
        var target = editableFiles.first ?? "base"
        if case .file(let name) = filter, editableFiles.contains(name) { target = name }
        if let source = duplicateOf { target = source.file }
        if let error = perform(.add(draft, copying: duplicateOf?.index), in: target, shown: duplicateOf) { return error }
        let added = snippets.last { $0.file == target }
        selectedID = added?.id
        if let added {
            let key = appearanceKey(added)
            updateLook { look in
                look.editedAt[key] = .now
                if let source = duplicateOf {
                    look.groupOf[key] = look.group(of: source)?.id
                    look.iconOf[key] = look.icon(of: source)
                } else if case .group(let id) = filter {
                    look.groupOf[key] = id
                }
            }
        }
        duplicateOf = nil
        return nil
    }

    private func duplicate(_ snippet: Snippet) {
        var draft = Draft(snippet)
        draft.trigger = ""
        draft.label = snippet.title + " copy"
        builderStart = draft
        duplicateOf = snippet
        showBuilder = true
    }

    private func delete(_ snippet: Snippet) {
        guard succeeded(perform(.delete(index: snippet.index), in: snippet.file, shown: snippet)) else { return }
        updateLook { $0.forget(appearanceKey(snippet)) }
        selectedID = nil
    }

    /// Changes groups, icons or edit dates and saves them to Snippet Studio's own file (never Espanso's).
    private func updateLook(_ change: (inout Appearance) -> Void) {
        change(&look)
        do {
            try saveAppearance(look)
            if savedNote == nil { confirm("Saved") } // keep "Saved to Espanso" when both happen
        } catch {
            alertMessage = "Your snippets are fine, but the colors and icons couldn’t be saved: \(error.localizedDescription)"
        }
    }

    /// A brief "Saved" note at the bottom of the window, so every change visibly registers.
    private func confirm(_ note: String) {
        savedNote = note
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            if savedNote == note { savedNote = nil }
        }
    }

    private func reload() {
        do {
            let library = try loadLibrary()
            snippets = library.snippets
            loadError = library.problems.isEmpty ? nil : "Couldn’t read: " + library.problems.joined(separator: "; ")
        } catch {
            loadError = "Couldn’t read your Espanso snippets: \(error.localizedDescription)"
        }
    }
}

struct SnippetDetail: View {
    let snippet: Snippet
    let library: [Snippet]
    var showFile = false
    @Binding var isEditing: Bool
    let groups: [SnippetGroup]
    @Binding var group: UUID?
    @Binding var icon: String?
    let colorName: String
    let onSave: (Draft) -> Bool
    let onDelete: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .center, spacing: 10) {
                    Badge(symbol: icon ?? defaultIcon, color: colorName, size: 30)
                    Text(snippet.title).font(.title2.bold())
                    Spacer()
                    if !isEditing && !snippet.runsCommand && !snippet.inSubfolder {
                        if !snippet.triggers.isEmpty {
                            Button("Edit") { isEditing = true }.keyboardShortcut("e").help("Edit (⌘E)")
                        }
                        Button("Delete…", role: .destructive, action: onDelete)
                    }
                }
                appearance
                if isEditing {
                    SnippetEditor(snippet: snippet, library: library,
                                  onSave: { draft in
                                      guard onSave(draft) else { return false }
                                      isEditing = false
                                      return true
                                  },
                                  onCancel: { isEditing = false })
                } else {
                    details
                }
            }
            .padding(22)
        }
    }

    /// Group and icon; these change Snippet Studio's own file at once, never the Espanso file.
    private var appearance: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Picker("Group", selection: $group) {
                    ForEach(groups) { group in
                        Label { Text(verbatim: group.name) } icon: {
                            Image(systemName: "circle.fill").foregroundStyle(groupColor(group.color))
                        }
                        .tag(Optional(group.id))
                    }
                    Text("No Group").tag(UUID?.none)
                }
                Text("Icon").font(.callout).foregroundStyle(.secondary)
                IconPicker(icon: $icon, color: colorName)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder private var details: some View {
        Text(verbatim: (snippet.triggers.isEmpty ? "Triggered by a pattern, not a shortcut" : "Type \(snippet.triggers.joined(separator: " or "))")
             + " · from \(snippet.file).yml")
            .foregroundStyle(.secondary)
        if snippet.inSubfolder {
            Label("Part of an Espanso package, which Espanso manages. Shown for reference only.", systemImage: "shippingbox")
                .foregroundStyle(.secondary)
        }
        if snippet.runsCommand {
            Label("This snippet runs a computer command. Shown for reference only.",
                  systemImage: "exclamationmark.shield")
                .foregroundStyle(.orange)
        }
        GroupBox("What it types") {
            Text(rendered).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        if showFile, let raw = rawYAML(of: snippet) { // shortcut: re-reads the file on each redraw; fine for one small file
            GroupBox("Espanso file") {
                Text(verbatim: raw)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        if !snippet.questions.isEmpty {
            GroupBox("Questions it will ask") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(snippet.questions.enumerated()), id: \.offset) { index, question in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: "\(index + 1). \(question.prompt)").bold()
                            Text(questionSummary(question)).font(.callout).foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// Snippet text with fill-ins shown as highlighted, readable tokens instead of `{{...}}`.
    private var rendered: AttributedString {
        segments(snippet.text).reduce(into: AttributedString()) { out, segment in
            switch segment {
            case .text(let text):
                out += AttributedString(text)
            case .token(let name, let isQuestion):
                let field = name.split(separator: ".").last.map(String.init) ?? name
                let type = snippet.variables[name] ?? "fill-in"
                var token = AttributedString(isQuestion ? " \(field)? " : " \(field) (\(type)) ")
                let color: Color = isQuestion ? .purple : .blue
                token.foregroundColor = color
                token.backgroundColor = color.opacity(0.12)
                out += token
            }
        }
    }
}
