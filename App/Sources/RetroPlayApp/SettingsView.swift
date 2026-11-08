// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI
import RetroPlayCore

@available(iOS 18.0, *)
struct SettingsView: View {
    @Binding var appearanceRaw: String
    let gameCounts: [SystemTab: Int]
    /// Games, Saves (incl. the PSP memory stick) and States — everything a user's library occupies.
    let storageDirectories: [URL]
    /// The library, so a PSP save a game owns isn't listed as waiting.
    let games: [LibraryGame]
    let onImport: () -> Void

    @AppStorage(PlaySettingsKey.sound) private var soundOn = true
    @AppStorage(PlaySettingsKey.respectSilentSwitch) private var respectSilentSwitch = false
    @AppStorage(PlaySettingsKey.haptics) private var haptics = true
    @AppStorage(PlaySettingsKey.flatControls) private var flatControls = false
    @AppStorage(BoxArtUpdater.enabledKey) private var downloadBoxArt = true
    @AppStorage(LibraryLayout.storageKey) private var layoutRaw = LibraryLayout.grid.rawValue
    @Environment(\.colorScheme) private var colorScheme

    @State private var storageUsed: Int64?
    @State private var keptSaves: [KeptSave] = []

    private var appearanceBinding: Binding<AppearancePreference> {
        Binding(
            get: { AppearancePreference(rawValue: appearanceRaw) ?? .dark },
            set: { appearanceRaw = $0.rawValue }
        )
    }

    var body: some View {
        NavigationStack {
            List {
                displaySection
                soundSection
                controlsSection
                librarySection
                savesSection
                aboutSection
            }
            .scrollContentBackground(.hidden)
            .background(RetroPlayTheme.canvas(for: colorScheme))
            .navigationTitle(retroPlayDisplayString("Settings"))
            .navigationBarTitleDisplayMode(.large)
            // Opaque SwiftUI toolbarBackground covers the large title; UIKit scroll-edge is clear.
            .toolbarColorScheme(colorScheme, for: .navigationBar)
            .retroPlayNavigationTitleChrome(for: colorScheme)
            .task { await measureStorage() }
            .task { await loadKeptSaves() }
        }
        .environment(\.font, RetroPlayFont.body)
        .retroPlayTypography()
        .tint(RetroPlayTheme.accent)
    }

    // MARK: Sections

    private var displaySection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                SettingsIconLabel("Appearance", symbol: "circle.lefthalf.filled", color: .indigo)
                Picker("Appearance", selection: appearanceBinding) {
                    ForEach(AppearancePreference.allCases) { pref in
                        Text(retroPlayDisplayString(pref.title)).tag(pref)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            .padding(.vertical, 4)
        } header: {
            sectionHeader("Display")
        }
        .listRowBackground(RetroPlayTheme.card(for: colorScheme))
    }

    private var soundSection: some View {
        Section {
            Toggle(isOn: $soundOn) {
                SettingsIconLabel("Game Sound", symbol: "speaker.wave.2.fill", color: .pink)
            }
            Toggle(isOn: $respectSilentSwitch) {
                SettingsIconLabel("Mute in Silent Mode", symbol: "bell.slash.fill", color: .orange)
            }
            .disabled(!soundOn)
        } header: {
            sectionHeader("Sound")
        }
        .listRowBackground(RetroPlayTheme.card(for: colorScheme))
    }

    private var controlsSection: some View {
        Section {
            Toggle(isOn: $haptics) {
                SettingsIconLabel("Button Haptics", symbol: "hand.tap.fill", color: .purple)
            }
            Toggle(isOn: $flatControls) {
                SettingsIconLabel("Flat Controls", symbol: "square.fill", color: .blue)
            }
        } header: {
            sectionHeader("Controls")
        }
        .listRowBackground(RetroPlayTheme.card(for: colorScheme))
    }

    private var layoutBinding: Binding<LibraryLayout> {
        Binding(
            get: { LibraryLayout(rawValue: layoutRaw) ?? .grid },
            set: { layoutRaw = $0.rawValue }
        )
    }

    private var librarySection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                SettingsIconLabel("Library Layout", symbol: "rectangle.stack.fill", color: .mint)
                Picker("Library Layout", selection: layoutBinding) {
                    ForEach(LibraryLayout.allCases) { layout in
                        Text(retroPlayDisplayString(layout.title)).tag(layout)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            .padding(.vertical, 4)
            LabeledContent {
                Text("\(gameCounts[.all] ?? 0)")
                    .font(RetroPlayFont.body)
            } label: {
                SettingsIconLabel("Games", symbol: "square.stack.fill", color: RetroPlayTheme.accent)
            }
            LabeledContent {
                Text(storageUsed.map { $0.formatted(.byteCount(style: .file)) } ?? "…")
                    .font(RetroPlayFont.body)
            } label: {
                SettingsIconLabel("Storage", symbol: "internaldrive.fill", color: .gray)
            }
            Toggle(isOn: $downloadBoxArt) {
                SettingsIconLabel("Download Box Art", symbol: "photo.on.rectangle.angled", color: .teal)
            }
            Button(action: onImport) {
                SettingsIconLabel("Import Games…", symbol: "plus", color: RetroPlayTheme.accent)
            }
        } header: {
            sectionHeader("Library")
        }
        .listRowBackground(RetroPlayTheme.card(for: colorScheme))
    }

    /// Saves imported for games not in the library, waiting for their game.
    private var savesSection: some View {
        Section {
            NavigationLink {
                KeptSavesView(games: games, saves: $keptSaves)
            } label: {
                LabeledContent {
                    Text("\(keptSaves.count)")
                        .font(RetroPlayFont.body)
                } label: {
                    SettingsIconLabel(KeptSavesView.title, symbol: "tray.full.fill", color: .orange)
                }
            }
            .accessibilityIdentifier("settings.keptSaves")
        } header: {
            sectionHeader("Saves")
        }
        .listRowBackground(RetroPlayTheme.card(for: colorScheme))
    }

    private func loadKeptSaves() async {
        let games = games
        keptSaves = await Task.detached(priority: .utility) {
            KeptSaves.list(games: games, paths: SavePaths())
        }.value
    }

    private var aboutSection: some View {
        Section {
            LabeledContent {
                Text(Self.versionString)
                    .font(RetroPlayFont.body)
            } label: {
                SettingsIconLabel("Version", symbol: "info.circle.fill", color: .blue)
            }
            DisclosureGroup {
                Text(
                    """
                    RetroPlay plays games you import yourself through Files. It does not include, sell, host or link to games, BIOS or firmware. Only import software you have the right to use.

                    Game Boy Advance, Nintendo 64, Nintendo DS and PlayStation Portable are trademarks of their respective owners, used here only to describe compatibility. RetroPlay is not affiliated with or endorsed by Nintendo or Sony.
                    """
                )
                .font(RetroPlayFont.footnote)
                .lineSpacing(2)
                .foregroundStyle(.secondary)
                .padding(.vertical, 6)
            } label: {
                SettingsIconLabel("Legal", symbol: "doc.text.fill", color: .gray)
            }
            NavigationLink {
                OpenSourceLicensesView()
            } label: {
                SettingsIconLabel("Open Source Licenses", symbol: "text.book.closed.fill", color: .indigo)
            }
        } header: {
            sectionHeader("About")
        }
        .listRowBackground(RetroPlayTheme.card(for: colorScheme))
    }

    // MARK: Helpers

    private func sectionHeader(_ title: String) -> some View {
        // Footnote rather than caption2: in capitals, 11 pt section names read as specks.
        Text(title.uppercased())
            .font(RetroPlayFont.footnote)
            .foregroundStyle(RetroPlayTheme.secondaryText(for: colorScheme))
    }

    private static var versionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    private func measureStorage() async {
        let directories = storageDirectories
        storageUsed = await Task.detached(priority: .utility) {
            directories.reduce(Int64(0)) { $0 + Self.directorySize($1) }
        }.value
    }

    private nonisolated static func directorySize(_ url: URL) -> Int64 {
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in enumerator {
            guard let values = try? file.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true
            else { continue }
            total += Int64(values.totalFileAllocatedSize ?? 0)
        }
        return total
    }
}

/// iOS Settings–style row label: white glyph on a coloured rounded square.
@available(iOS 18.0, *)
struct SettingsIconLabel: View {
    let title: String
    let symbol: String
    let color: Color
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(_ title: String, symbol: String, color: Color) {
        self.title = title
        self.symbol = symbol
        self.color = color
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(color, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .accessibilityHidden(true)
            Text(title)
                .font(RetroPlayFont.body)
                .foregroundStyle(.primary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 2)
                .minimumScaleFactor(0.6)
        }
    }
}

extension SystemTab {
    init(_ system: SystemID) {
        switch system {
        case .gba: self = .gba
        case .n64: self = .n64
        case .nds: self = .nds
        case .psp: self = .psp
        case .nes: self = .nes
        case .snes: self = .snes
        case .genesis: self = .genesis
        case .atari7800: self = .atari7800
        case .ps1: self = .ps1
        }
    }
}
