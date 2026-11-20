import SwiftUI
import WalletWeatherKit

/// Tags on the iPhone (Plans/phone-tags.md, phase 2, #251), with or
/// without a server (decided 2026-11-20): chips on rows, a picker on lines
/// and bills with New tag…, and the Tags page in Settings.

/// A tag's colour: its own, or a steady one from its name.
func tagColor(_ tag: TagInfo) -> Color { Palette.category(tag.color, name: tag.name) }

/// Small chips in each tag's colour, in name order.
struct TagChips: View {
    let tags: [TagInfo]

    var body: some View {
        if !tags.isEmpty {
            HStack(spacing: 4) {
                ForEach(tags.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) { tag in
                    Text(tag.name)
                        .font(.caption2.weight(.medium))
                        .lineLimit(1)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .foregroundStyle(tagColor(tag))
                        .background(tagColor(tag).opacity(0.15), in: Capsule())
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Tags: " + tags.map(\.name).joined(separator: ", "))
        }
    }
}

/// A form row: the chosen tags as chips (or None), opening the picker.
struct TagsRow: View {
    @Environment(AppModel.self) private var model
    @Binding var selected: [Int]
    @State private var all: [TagInfo] = []
    @State private var picking = false

    var body: some View {
        Button { picking = true } label: {
            HStack {
                Text("Tags").foregroundStyle(Color.primary)
                Spacer()
                let chosen = all.filter { selected.contains($0.id) }
                if chosen.isEmpty { Text("None").foregroundStyle(.secondary) } else { TagChips(tags: chosen) }
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .task { await load() }
        .sheet(isPresented: $picking, onDismiss: { Task { await load() } }) { TagPickerSheet(selected: $selected) }
    }

    private func load() async { all = (try? await model.client?.tags()) ?? all }
}

/// Choose tags: every tag with a tick, and New tag… at the end.
struct TagPickerSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Binding var selected: [Int]
    @State private var all: [TagInfo] = []
    @State private var making = false
    @State private var problem: String?

    var body: some View {
        NavigationStack {
            List {
                if let problem { Text(problem).foregroundStyle(Palette.bad) }
                ForEach(all) { tag in
                    Button { toggle(tag.id) } label: {
                        HStack {
                            Circle().fill(tagColor(tag)).frame(width: 10, height: 10)
                            Text(tag.name).foregroundStyle(Color.primary)
                            Spacer()
                            if selected.contains(tag.id) { Image(systemName: "checkmark").foregroundStyle(Palette.accent) }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Button { making = true } label: { Label("New tag…", systemImage: "plus.circle") }
            }
            .navigationTitle("Tags")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task { await load() }
            .sheet(isPresented: $making) {
                TagEditSheet(tag: nil) { made in
                    if let made, !selected.contains(made.id) { selected.append(made.id) }
                    Task { await load() }
                }
            }
        }
    }

    private func toggle(_ id: Int) {
        if let i = selected.firstIndex(of: id) { selected.remove(at: i) } else { selected.append(id) }
    }

    private func load() async {
        do { all = try await model.client?.tags() ?? [] } catch { problem = AppModel.describe(error) }
    }
}

/// Make a tag, or change one: its name and colour.
struct TagEditSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let tag: TagInfo?
    let onSaved: (TagInfo?) -> Void
    @State private var name = ""
    @State private var color: String?
    @State private var saving = false
    @State private var problem: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name, such as Work trip", text: $name)
                } footer: {
                    if let problem { Text(problem).foregroundStyle(Palette.bad) }
                }
                Section("Colour") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 12) {
                        ForEach(TagColors.all, id: \.self) { hex in
                            let swatch = Palette.category(hex, name: "")
                            Circle().fill(swatch).frame(width: 28, height: 28)
                                .overlay { if color == hex { Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.white) } }
                                .onTapGesture { color = color == hex ? nil : hex }
                                .accessibilityLabel(hex)
                                .accessibilityAddTraits(color == hex ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle(tag == nil ? "New tag" : "Change tag")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(tag == nil ? "Add" : "Save") { Task { await save() } }
                        .disabled(saving || name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                name = tag?.name ?? ""
                color = tag?.color
            }
        }
    }

    private func save() async {
        guard let client = model.client else { return }
        saving = true
        defer { saving = false }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            if let tag {
                try await client.updateTag(tag.id, name: trimmed, color: color)
                onSaved(TagInfo(id: tag.id, name: trimmed, color: color))
            } else {
                onSaved(try await client.createTag(name: trimmed, color: color))
            }
            dismiss()
        } catch {
            problem = AppModel.describe(error)
        }
    }
}

/// Settings → Tags: every tag; add, change, delete.
struct TagsPage: View {
    @Environment(AppModel.self) private var model
    @State private var tags: Loadable<[TagInfo]> = .loading
    @State private var editing: TagInfo?
    @State private var adding = false
    @State private var deleting: TagInfo?
    @State private var problem: String?

    private var canEdit: Bool { model.me?.isReadOnly != true }

    var body: some View {
        Group {
            switch tags {
            case .loading:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            case let .failed(error):
                ProblemView(error: error) { Task { await load() } }
            case let .loaded(list):
                List {
                    if list.isEmpty {
                        Text("No tags yet. Tags mark lines and bills across categories, such as a trip or a project.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(list) { tag in
                        Button { if canEdit { editing = tag } } label: {
                            HStack {
                                Circle().fill(tagColor(tag)).frame(width: 12, height: 12)
                                Text(tag.name).foregroundStyle(Color.primary)
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .swipeActions {
                            if canEdit {
                                Button("Delete", role: .destructive) { deleting = tag }
                            }
                        }
                    }
                    if let problem { Text(problem).foregroundStyle(Palette.bad) }
                }
            }
        }
        .navigationTitle("Tags")
        .toolbar {
            if canEdit {
                ToolbarItem(placement: .topBarTrailing) { Button("Add tag", systemImage: "plus") { adding = true } }
            }
        }
        .task(id: model.generation) { await load() }
        .refreshable { await load() }
        .sheet(item: $editing) { tag in TagEditSheet(tag: tag) { _ in Task { await load() } } }
        .sheet(isPresented: $adding) { TagEditSheet(tag: nil) { _ in Task { await load() } } }
        .confirmationDialog(deleting.map { "Delete \($0.name)?" } ?? "", isPresented: Binding(
            get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible, presenting: deleting) { tag in
            Button("Delete tag", role: .destructive) { Task { await delete(tag) } }
        } message: { _ in
            Text("It comes off every line and bill, and its auto-tag rules go too. The lines and bills stay.")
        }
    }

    private func load() async {
        guard let client = model.client else { return }
        do { tags = .loaded(try await client.tags()) } catch { tags = .failed(error) }
    }

    private func delete(_ tag: TagInfo) async {
        do {
            try await model.client?.deleteTag(tag.id)
            model.reload()
        } catch {
            problem = AppModel.describe(error)
        }
        await load()
    }
}
