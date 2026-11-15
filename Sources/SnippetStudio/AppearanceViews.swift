import SnippetCore
import SwiftUI

func groupColor(_ name: String) -> Color {
    switch name {
    case "red": .red
    case "orange": .orange
    case "yellow": .yellow
    case "green": .green
    case "mint": .mint
    case "teal": .teal
    case "cyan": .cyan
    case "blue": .blue
    case "indigo": .indigo
    case "purple": .purple
    case "pink": .pink
    case "brown": .brown
    default: .gray
    }
}

/// The light colors get dark text; the rest get white text over a shaded lower half, so the words stay readable.
func usesDarkInk(_ name: String) -> Bool { ["yellow", "mint", "cyan"].contains(name) }

func ink(_ name: String) -> Color { usesDarkInk(name) ? Color.black.opacity(0.8) : .white }

let defaultIcon = "text.quote"

/// The icons a snippet can wear (Apple's SF Symbols), with names for menus and VoiceOver.
let snippetIcons: [(symbol: String, name: String)] = [
    ("text.quote", "Quote"), ("envelope.fill", "Envelope"), ("bubble.left.fill", "Message"), ("phone.fill", "Phone"),
    ("clock.fill", "Clock"), ("calendar", "Calendar"), ("checkmark.seal.fill", "Seal"), ("signature", "Signature"),
    ("square.and.pencil", "Pencil"), ("doc.text.fill", "Document"), ("doc.on.doc.fill", "Copies"), ("paperclip", "Paperclip"),
    ("archivebox.fill", "Archive"), ("folder.fill", "Folder"), ("tray.fill", "Tray"), ("list.bullet", "List"),
    ("exclamationmark.shield.fill", "Objection"), ("lock.shield.fill", "Privacy"), ("building.columns.fill", "Court"),
    ("hammer.fill", "Gavel"), ("paragraphsign", "Paragraph"), ("number", "Number"), ("briefcase.fill", "Briefcase"),
    ("person.crop.circle.badge.checkmark", "Client"), ("person.2.fill", "People"), ("dollarsign.circle.fill", "Money"),
    ("flag.fill", "Flag"), ("star.fill", "Star"), ("tag.fill", "Tag"), ("bolt.fill", "Bolt"),
]

/// A small rounded-square icon in a color, as in the sidebar and lists.
struct Badge: View {
    let symbol: String
    let color: String
    var size: CGFloat = 20

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.55, weight: .semibold))
            .foregroundStyle(ink(color))
            .frame(width: size, height: size)
            .background(groupColor(color).gradient, in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// One snippet as a colored tile in the Gallery.
struct SnippetTile: View {
    let snippet: Snippet
    let color: String
    let icon: String
    let isSelected: Bool
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .top) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 34, height: 34)
                    .background(.white.opacity(0.22), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                Spacer()
                Text(verbatim: snippet.triggers.first ?? "pattern")
                    .font(.system(.caption, design: .monospaced).weight(.medium))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(.black.opacity(0.18), in: Capsule())
            }
            Spacer(minLength: 10)
            Text(verbatim: snippet.title).font(.headline).lineLimit(1)
            Text(verbatim: plainPreview(snippet.text)).font(.caption).opacity(0.95).lineLimit(1)
        }
        .foregroundStyle(ink(color))
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 128, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(groupColor(color).gradient)
                .overlay(LinearGradient(colors: [.clear, .black.opacity(usesDarkInk(color) ? 0 : 0.28)],
                                        startPoint: .center, endPoint: .bottom))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 19, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: 3)
                    .padding(-4)
            }
        }
        .shadow(color: .black.opacity(hovering ? 0.25 : 0.08), radius: hovering ? 12 : 2, y: hovering ? 6 : 1)
        .offset(y: hovering && !reduceMotion ? -2 : 0)
        .animation(.snappy(duration: 0.18), value: hovering)
        .onHover { hovering = $0 }
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// Snippet text on one line, with fill-ins shown as [name] instead of `{{form1.name}}`.
func plainPreview(_ text: String) -> String {
    segments(text).map { segment in
        switch segment {
        case .text(let text): text
        case .token(let name, _): "[" + (name.split(separator: ".").last.map(String.init) ?? name) + "]"
        }
    }
    .joined()
    .replacingOccurrences(of: "$|$", with: "")
    .split(whereSeparator: \.isNewline).joined(separator: " ")
}

/// Grid of icons to choose from.
struct IconPicker: View {
    @Binding var icon: String?
    let color: String

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(34), spacing: 8), count: 8), alignment: .leading, spacing: 8) {
            ForEach(snippetIcons, id: \.symbol) { option in
                let chosen = (icon ?? defaultIcon) == option.symbol
                Button { icon = option.symbol } label: {
                    Image(systemName: option.symbol)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(chosen ? ink(color) : .secondary)
                        .frame(width: 34, height: 34)
                        .background(chosen ? AnyShapeStyle(groupColor(color).gradient) : AnyShapeStyle(HierarchicalShapeStyle.quaternary),
                                    in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .buttonStyle(.plain)
                .help(option.name)
                .accessibilityLabel(option.name)
                .accessibilityAddTraits(chosen ? .isSelected : [])
            }
        }
    }
}

/// Name a group and pick its color.
struct GroupSheet: View {
    let isNew: Bool
    let onSave: (SnippetGroup) -> Void
    @State private var group: SnippetGroup
    @Environment(\.dismiss) private var dismiss

    init(group: SnippetGroup, isNew: Bool, onSave: @escaping (SnippetGroup) -> Void) {
        self.isNew = isNew
        self.onSave = onSave
        _group = State(initialValue: group)
    }

    private var name: String { group.name.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(isNew ? "New Group" : "Edit Group").font(.title3.bold())
            TextField("Name, for example: Discovery", text: $group.name).textFieldStyle(.roundedBorder)
            Text("Color").font(.headline)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(26), spacing: 10), count: 7), alignment: .leading, spacing: 10) {
                ForEach(groupColors, id: \.self) { color in
                    Button { group.color = color } label: {
                        Circle().fill(groupColor(color).gradient)
                            .frame(width: 24, height: 24)
                            .padding(3)
                            .overlay(Circle().strokeBorder(group.color == color ? groupColor(color) : .clear, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(color.capitalized)
                    .accessibilityAddTraits(group.color == color ? .isSelected : [])
                }
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button(isNew ? "Create" : "Save") {
                    group.name = name
                    onSave(group)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 320)
    }
}
