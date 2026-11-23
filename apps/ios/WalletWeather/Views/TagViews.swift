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

/// Settings → Tags: every tag (add, change, delete), and the auto-tag
/// rules below them (#252).
struct TagsPage: View {
    @Environment(AppModel.self) private var model
    @State private var tags: Loadable<[TagInfo]> = .loading
    @State private var rules: [TagRule] = []
    @State private var categories: [TransactionCategory] = []
    @State private var editingRule: TagRule?
    @State private var addingRule = false
    @State private var applying = false
    @State private var applied: String?
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
                    Group {
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
                        rulesSection(list)
                    }
                    .listRowBackground(Palette.row)
                }
                .scrollContentBackground(.hidden)
            }
        }
        .background(PageBackground().ignoresSafeArea())
        .navigationTitle("Tags")
        .toolbar {
            if canEdit {
                ToolbarItem(placement: .topBarTrailing) { Button("Add tag", systemImage: "plus") { adding = true } }
            }
        }
        .task(id: model.generation) { await load() }
        .refreshable { await load() }
        .sheet(item: $editing) { tag in TagEditSheet(tag: tag) { _ in Task { await load() } } }
        .sheet(item: $editingRule) { rule in
            RuleEditSheet(rule: rule, tags: tags.value ?? [], categories: categories) { Task { await load() } }
        }
        .sheet(isPresented: $addingRule) {
            RuleEditSheet(rule: nil, tags: tags.value ?? [], categories: categories) { Task { await load() } }
        }
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
        rules = (try? await client.tagRules()) ?? []
        categories = (try? await client.categories()) ?? categories
    }

    @ViewBuilder
    private func rulesSection(_ list: [TagInfo]) -> some View {
        Section {
            ForEach(rules) { rule in
                Button { if canEdit { editingRule = rule } } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("“\(rule.descriptionPattern)”").foregroundStyle(Color.primary)
                            Image(systemName: "arrow.right").font(.caption).foregroundStyle(.secondary)
                            TagChips(tags: [TagInfo(id: rule.tagId, name: rule.tagName ?? "?", color: rule.tagColor)])
                            if !rule.active { Text("Off").font(.caption).foregroundStyle(.secondary) }
                        }
                        Text([rule.name, rule.categoryName.map { "only in \($0)" }].compactMap { $0 }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .swipeActions {
                    if canEdit {
                        Button("Delete", role: .destructive) { Task { await deleteRule(rule) } }
                    }
                }
            }
            if canEdit {
                Button { addingRule = true } label: { Label("Add a rule", systemImage: "plus.circle") }
                    .disabled(list.isEmpty)
                if !rules.isEmpty {
                    Button { Task { await applyRules() } } label: {
                        Label(applying ? "Applying…" : "Apply to existing lines", systemImage: "wand.and.stars")
                    }
                    .disabled(applying)
                }
            }
            if let applied { Text(applied).font(.footnote).foregroundStyle(.secondary) }
        } header: {
            Text("Auto-tag rules")
        } footer: {
            Text(list.isEmpty ? "Make a tag first, then a rule to add it by itself."
                 : "A rule adds its tag to a line whose description contains the words, when it's added, changed or imported. Apply to existing lines adds it to the ones already here.")
        }
    }

    private func deleteRule(_ rule: TagRule) async {
        do { try await model.client?.deleteTagRule(rule.id) } catch { problem = AppModel.describe(error) }
        await load()
    }

    private func applyRules() async {
        guard let client = model.client else { return }
        applying = true
        defer { applying = false }
        do {
            let done = try await client.applyTagRules()
            applied = done.tagsAdded == 0 ? "Nothing new to tag." : "Added \(done.tagsAdded) tag\(done.tagsAdded == 1 ? "" : "s") to existing lines."
            model.reload()
        } catch {
            problem = AppModel.describe(error)
        }
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

/// Add or change an auto-tag rule: the words to look for, the tag, and
/// optionally a category the line must be in and a name.
struct RuleEditSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let rule: TagRule?
    let tags: [TagInfo]
    let categories: [TransactionCategory]
    let onSaved: () -> Void
    @State private var body_ = TagRuleBody()
    @State private var saving = false
    @State private var problem: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Words to look for, such as café", text: $body_.descriptionPattern)
                        .textInputAutocapitalization(.never)
                    Picker("Add the tag", selection: $body_.tagId) {
                        if body_.tagId == nil { Text("Choose").tag(Int?.none) }
                        ForEach(tags) { Text($0.name).tag(Optional($0.id)) }
                    }
                } footer: {
                    Text("A line whose description contains these words, in any case, gets the tag.")
                }
                Section {
                    Picker("Only in category", selection: $body_.categoryId) {
                        Text("Any").tag(Int?.none)
                        ForEach(categories) { Text($0.name).tag(Optional($0.id)) }
                    }
                    TextField("Name (optional)", text: $body_.name)
                    Toggle("On", isOn: $body_.active)
                } footer: {
                    if let problem = problem ?? (body_.descriptionPattern.isEmpty ? nil : body_.problem) {
                        Text(problem).foregroundStyle(Palette.bad)
                    }
                }
            }
            .navigationTitle(rule == nil ? "New rule" : "Change rule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(rule == nil ? "Add" : "Save") { Task { await save() } }.disabled(saving || body_.problem != nil)
                }
            }
            .onAppear { body_ = rule.map(TagRuleBody.init) ?? TagRuleBody(tagId: tags.count == 1 ? tags[0].id : nil) }
        }
    }

    private func save() async {
        guard let client = model.client else { return }
        saving = true
        defer { saving = false }
        do {
            if let rule { try await client.updateTagRule(rule.id, body_) } else { try await client.createTagRule(body_) }
            onSaved()
            dismiss()
        } catch {
            problem = AppModel.describe(error)
        }
    }
}
