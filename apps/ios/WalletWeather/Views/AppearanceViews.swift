import SwiftUI
import WalletWeatherKit

/// Every look as a tile: a tiny screen in the look's own colours with its
/// name under it, the chosen one ringed in the accent colour. Tapping one
/// applies it at once (which ticks Getting started's look task). Used by
/// Settings → Appearance and Getting started's Choose a look (#296,
/// finding R19). Three across on a phone, more on a wider width.
struct LookGrid: View {
    @Environment(AppSettings.self) private var settings

    private let columns = [GridItem(.adaptive(minimum: 92), spacing: 12, alignment: .top)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .center, spacing: 16) {
            ForEach(Look.allCases) { look in
                LookTile(look: look, selected: settings.look == look,
                         swatches: look.swatches(server: settings.serverTheme)) {
                    settings.look = look
                }
            }
        }
        .padding(.vertical, 4)
    }
}

/// One look: one button, named for the look, "selected" when chosen.
private struct LookTile: View {
    let look: Look
    let selected: Bool
    let swatches: [LookPreview.Swatch]
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                LookMiniature(swatches: swatches)
                    .aspectRatio(1.3, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.18), lineWidth: 1))
                    .padding(3)
                    .overlay {
                        if selected {
                            RoundedRectangle(cornerRadius: 15, style: .continuous)
                                .strokeBorder(Palette.accent, lineWidth: 3)
                        }
                    }
                Text(look.title)
                    .font(.caption.weight(selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Palette.accent : (Palette.text ?? Color.primary))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(look.title)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

/// The tiny screens of a look: one, or two split down the middle (Light on
/// the left, Dark on the right).
private struct LookMiniature: View {
    let swatches: [LookPreview.Swatch]

    var body: some View {
        ZStack {
            if let first = swatches.first { MiniScreen(swatch: first) }
            if swatches.count > 1 {
                MiniScreen(swatch: swatches[1])
                    .mask(HStack(spacing: 0) { Color.clear; Color.black })
            }
        }
    }
}

/// A page-coloured screen holding a card with a short text bar, a green and
/// a red bar side by side, and an accent bar.
private struct MiniScreen: View {
    let swatch: LookPreview.Swatch

    var body: some View {
        GeometryReader { box in
            let inner = box.size.width * 0.78
            ZStack {
                Color(UIColor(hex: swatch.page))
                VStack(alignment: .leading, spacing: box.size.height * 0.07) {
                    bar(swatch.text, width: inner * 0.5, height: box.size.height * 0.07)
                    HStack(spacing: 4) {
                        bar(swatch.good, width: inner * 0.34, height: box.size.height * 0.07)
                        bar(swatch.bad, width: inner * 0.34, height: box.size.height * 0.07)
                    }
                    bar(swatch.accent, width: inner * 0.62, height: box.size.height * 0.09)
                }
                .padding(box.size.width * 0.09)
                .frame(width: inner, alignment: .leading)
                .background(Color(UIColor(hex: swatch.card)), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
        }
    }

    private func bar(_ hex: UInt32, width: CGFloat, height: CGFloat) -> some View {
        Capsule().fill(Color(UIColor(hex: hex))).frame(width: width, height: height)
    }
}

// MARK: - My themes (ios-settings phase 4, #297)

/// What the theme editor opens on: a theme being made (a copy of a look,
/// not saved until Save) or one being changed.
private struct ThemeDraft: Identifiable {
    let theme: CustomTheme
    let isNew: Bool
    var id: UUID { theme.id }
}

/// Settings → Appearance → My themes, under the built-in looks: a row per
/// theme the person made (tap to use it; ⋯ or a long press to edit,
/// duplicate or delete it) and New theme, which starts as a copy of any
/// look. Debug only: `WW_DEBUG_THEME_EDITOR=custom-light`, `custom-dark`,
/// a theme's name, or `new` opens the editor at once.
struct MyThemes: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.colorScheme) private var scheme
    @State private var draft: ThemeDraft?
    @State private var deleting: CustomTheme?
    @State private var debugOpened = false

    var body: some View {
        SectionTitle("My themes")
        VStack(spacing: 0) {
            ForEach(settings.customThemes) { theme in
                row(theme)
                Divider()
            }
            newTheme
        }
        .card()
        SettingNote("Make a look of your own from six colours. Your themes are kept in iCloud, names and colours only, so they reach your other iPhones; with iCloud off they stay on this iPhone.")
            .sheet(item: $draft) { draft in
                ThemeEditor(draft: draft)
            }
            .confirmationDialog(deleting.map { "Delete “\($0.name)”?" } ?? "", isPresented: Binding(
                get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
                Button("Delete theme", role: .destructive) {
                    if let deleting { settings.deleteTheme(deleting.id) }
                }
            } message: {
                Text(inUse(deleting)
                     ? "It's the look in use, so the app goes back to Match this iPhone. It's deleted on your other iPhones too."
                     : "It's deleted on your other iPhones too.")
            }
            .task { openForDebug() }
    }

    private func inUse(_ theme: CustomTheme?) -> Bool {
        guard let theme, case let .custom(current) = settings.look else { return false }
        return current.id == theme.id
    }

    private func row(_ theme: CustomTheme) -> some View {
        let selected = inUse(theme)
        return HStack(spacing: 12) {
            Button {
                settings.look = .custom(theme)
            } label: {
                HStack(spacing: 12) {
                    LookMiniature(swatches: [LookPreview.Swatch(theme.colors)])
                        .frame(width: 46, height: 34)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.18), lineWidth: 1))
                    Text(theme.name)
                        .foregroundStyle(Palette.text ?? Color.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if selected {
                        Image(systemName: "checkmark").fontWeight(.semibold).foregroundStyle(Palette.accent)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(theme.name)
            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            Menu {
                actions(theme)
            } label: {
                Image(systemName: "ellipsis.circle").font(.title3)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("More for \(theme.name)")
        }
        .frame(minHeight: 50)
        .contextMenu { actions(theme) }
    }

    @ViewBuilder private func actions(_ theme: CustomTheme) -> some View {
        Button("Edit", systemImage: "pencil") { draft = ThemeDraft(theme: theme, isNew: false) }
        Button("Duplicate", systemImage: "plus.square.on.square") {
            var copy = theme
            copy.id = UUID()
            copy.name = "\(theme.name) copy"
            settings.saveTheme(copy)
        }
        Button("Delete", systemImage: "trash", role: .destructive) { deleting = theme }
    }

    /// New theme: a menu of every look to start from, the built-in ones
    /// and then the person's own.
    private var newTheme: some View {
        Menu {
            Section("Start from") {
                ForEach(Look.allCases + settings.customThemes.map(Look.custom)) { look in
                    Button(look.title) { draft = ThemeDraft(theme: copy(of: look), isNew: true) }
                }
            }
        } label: {
            Label("New theme", systemImage: "plus")
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
        }
    }

    /// A new, unsaved theme with a look's colours, named after it.
    private func copy(of look: Look) -> CustomTheme {
        let colors = look.colors(dark: scheme == .dark, server: settings.serverTheme)
        let base: String = switch look {
        case .system: scheme == .dark ? Look.dark.title : Look.light.title
        case .web: Look.matching(ServerTheme(settings.serverTheme)).title
        default: look.title
        }
        return CustomTheme(name: "My \(base)", copying: colors)
    }

    private func openForDebug() {
        guard !debugOpened, let name = AppModel.debugSetting("WW_DEBUG_THEME_EDITOR") else { return }
        debugOpened = true
        if name == "new" {
            draft = ThemeDraft(theme: copy(of: settings.shownLook), isNew: true)
        } else if let theme = settings.customThemes.first(where: { $0.name == name || $0.rawValue == name })
                    ?? CustomThemeStore.sample(named: name) {
            draft = ThemeDraft(theme: theme, isNew: false)
        }
    }
}

/// The theme editor: a live preview, the name, the six colours (system
/// colour pickers) and a readability line, which warns about a faint pair
/// but still lets the theme save (decided 2026-11-23).
private struct ThemeEditor: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @State private var theme: CustomTheme
    private let isNew: Bool

    init(draft: ThemeDraft) {
        _theme = State(initialValue: draft.theme)
        isNew = draft.isNew
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ThemeSample(theme: theme)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Preview of \(CustomTheme.cleanName(theme.name) ?? "the theme")")
                    SectionTitle("Name")
                    TextField("Theme name", text: $theme.name)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .frame(minHeight: 44)
                        .card()
                    SectionTitle("Colours")
                    VStack(spacing: 0) {
                        colorRow("Page", \.page)
                        Divider()
                        colorRow("Card", \.card)
                        Divider()
                        colorRow("Text", \.text)
                        Divider()
                        colorRow("Accent", \.accent)
                        Divider()
                        colorRow("Money in", \.moneyIn)
                        Divider()
                        colorRow("Money out", \.moneyOut)
                    }
                    .card()
                    ReadabilityLine(theme: theme)
                    SettingNote("Outlines and warnings are worked out from these colours.")
                }
                .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 24)
            }
            .debugScrollAnchor()
            .background(PageBackground().ignoresSafeArea())
            .navigationTitle(isNew ? "New theme" : "Edit theme")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let name = CustomTheme.cleanName(theme.name) else { return }
                        var saved = theme
                        saved.name = name
                        settings.saveTheme(saved)
                        dismiss()
                    }
                    .disabled(CustomTheme.cleanName(theme.name) == nil)
                }
            }
        }
    }

    private func colorRow(_ title: String, _ keyPath: WritableKeyPath<CustomTheme, UInt32>) -> some View {
        ColorPicker(selection: Binding(
            get: { Color(UIColor(hex: theme[keyPath: keyPath])) },
            set: { theme[keyPath: keyPath] = UIColor($0).rgbHex }), supportsOpacity: false) {
            HStack {
                Text(title)
                Spacer()
                Text(CustomTheme.hex(theme[keyPath: keyPath]).uppercased())
                    .font(.footnote.monospaced()).foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        }
        .frame(minHeight: 44)
    }
}

/// Under the colours: whether text, money in, money out and the accent
/// read clearly (4.5:1, WCAG AA), naming each faint pair.
private struct ReadabilityLine: View {
    let theme: CustomTheme

    var body: some View {
        let faint = theme.faintPairs
        Group {
            if faint.isEmpty {
                Label("Everything reads clearly: text, money in and money out on the card, and the accent on the page.",
                      systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
            } else {
                let pairs = faint.map { "\($0.title) (\(String(format: "%.1f", theme.ratio($0))):1)" }
                Label("Hard to read: \(pairs.formatted(.list(type: .and))). Under 4.5:1 is faint for some eyes; the theme still saves.",
                      systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(Palette.warn)
            }
        }
        .font(.footnote)
        .padding(.horizontal, 4)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// The editor's live preview: a page in the theme's colours holding a card
/// with a heading, a line of money in, a line of money out and a button in
/// the accent colour, drawn in the theme whatever look the app is in.
private struct ThemeSample: View {
    let theme: CustomTheme

    var body: some View {
        let color = { (hex: UInt32) in Color(UIColor(hex: hex)) }
        VStack(alignment: .leading, spacing: 10) {
            Text(CustomTheme.cleanName(theme.name) ?? "Your theme")
                .font(.headline).foregroundStyle(color(theme.text))
            HStack {
                Text("Paycheck").foregroundStyle(color(theme.text))
                Spacer()
                Text("+2,400.00").monospacedDigit().foregroundStyle(color(theme.moneyIn))
            }
            HStack {
                Text("Groceries").foregroundStyle(color(theme.text))
                Spacer()
                Text("−84.20").monospacedDigit().foregroundStyle(color(theme.moneyOut))
            }
            Text("Add a line")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color(theme.isDark ? 0x000000 : 0xFFFFFF))
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(color(theme.accent), in: Capsule())
        }
        .padding(16)
        .background(color(theme.card), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(color(theme.outline), lineWidth: 1))
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(color(theme.page), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .environment(\.colorScheme, theme.isDark ? .dark : .light)
    }
}

extension UIColor {
    /// This colour as `0xRRGGBB` in sRGB, clamped (a colour picker can hand
    /// back wider colours).
    var rgbHex: UInt32 {
        var (r, g, b, a): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        guard getRed(&r, green: &g, blue: &b, alpha: &a) else { return 0 }
        func byte(_ v: CGFloat) -> UInt32 { UInt32((min(max(v, 0), 1) * 255).rounded()) }
        return byte(r) << 16 | byte(g) << 8 | byte(b)
    }
}
