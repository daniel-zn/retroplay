// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI
import RetroPlayCore

@available(iOS 18.0, *)
struct SettingsView: View {
    @Binding var appearanceRaw: String
    let gameCounts: [SystemTab: Int]
    /// Games, Saves (incl. the PSP memory stick) and States — everything a user's library occupies.
    let storageDirectories: [URL]
    let onImport: () -> Void

    @AppStorage(PlaySettingsKey.sound) private var soundOn = true
    @AppStorage(PlaySettingsKey.respectSilentSwitch) private var respectSilentSwitch = false
    @AppStorage(PlaySettingsKey.haptics) private var haptics = true
    @AppStorage(PlaySettingsKey.padOpacity) private var padOpacity = 0.75
    @AppStorage(PlaySettingsKey.smoothScreen) private var smoothScreen = false
    @AppStorage(PlaySettingsKey.touchWithController) private var touchWithController = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    @State private var storageUsed: Int64?

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
                systemsSection
                aboutSection
            }
            .scrollContentBackground(.hidden)
            .background(RetroPlayTheme.canvas(for: colorScheme))
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            // Opaque SwiftUI toolbarBackground covers the large title; UIKit scroll-edge is clear.
            .toolbarColorScheme(colorScheme, for: .navigationBar)
            .retroPlayNavigationTitleChrome(for: colorScheme)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: {
                        Text("Done")
                            .font(RetroPlayFont.body)
                    }
                }
            }
            .task { await measureStorage() }
        }
        .environment(\.font, RetroPlayFont.caption)
        .tint(RetroPlayTheme.accent)
    }

    // MARK: Sections

    private var displaySection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                SettingsIconLabel("Appearance", symbol: "circle.lefthalf.filled", color: .indigo)
                Picker("Appearance", selection: appearanceBinding) {
                    ForEach(AppearancePreference.allCases) { pref in
                        Text(pref.title).tag(pref)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            .padding(.vertical, 4)
            Toggle(isOn: $smoothScreen) {
                SettingsIconLabel("Smooth Screen", symbol: "sparkles.tv", color: .teal)
            }
        } header: {
            sectionHeader("Display")
        } footer: {
            sectionFooter("Smooth Screen blends pixels when the game is scaled up. Off keeps them sharp.")
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
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    SettingsIconLabel("Landscape Controls", symbol: "rectangle.landscape.rotate", color: .blue)
                    Spacer()
                    Text("\(Int((padOpacity * 100).rounded()))%")
                        .font(RetroPlayFont.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(value: $padOpacity, in: 0.25...1) {
                    Text("Landscape controls opacity")
                }
            }
            .padding(.vertical, 4)
            Toggle(isOn: $touchWithController) {
                SettingsIconLabel("Touch Pad with Controller", symbol: "gamecontroller.fill", color: .green)
            }
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 8) {
                    helpRow("Controllers", "MFi, Xbox, PlayStation and Switch Pro. Buttons map by position; Home opens the menu.")
                    helpRow("Keyboard", "Arrows move · Z X A S face buttons · Q W shoulders · Return Start · Esc menu.")
                    helpRow("N64", "Left trigger is Z; the right stick is the C buttons.")
                }
                .padding(.vertical, 6)
            } label: {
                SettingsIconLabel("Controller & Keyboard", symbol: "keyboard", color: .gray)
            }
        } header: {
            sectionHeader("Controls")
        } footer: {
            sectionFooter("The touch pad hides while a controller is connected unless Touch Pad with Controller is on.")
        }
        .listRowBackground(RetroPlayTheme.card(for: colorScheme))
    }

    private var librarySection: some View {
        Section {
            LabeledContent {
                Text("\(gameCounts[.all] ?? 0)")
                    .font(RetroPlayFont.caption)
            } label: {
                SettingsIconLabel("Games", symbol: "square.stack.fill", color: RetroPlayTheme.accent)
            }
            LabeledContent {
                Text(storageUsed.map { $0.formatted(.byteCount(style: .file)) } ?? "…")
                    .font(RetroPlayFont.caption)
            } label: {
                SettingsIconLabel("Storage", symbol: "internaldrive.fill", color: .gray)
            }
            Button(action: onImport) {
                SettingsIconLabel("Import Games…", symbol: "plus", color: RetroPlayTheme.accent)
            }
        } header: {
            sectionHeader("Library")
        }
        .listRowBackground(RetroPlayTheme.card(for: colorScheme))
    }

    private var systemsSection: some View {
        Section {
            ForEach(SystemID.allCases) { system in
                let ready = NativeDriverRegistry.isRegistered(system)
                HStack(spacing: 12) {
                    SystemBadge(system: system)
                        .frame(width: 44, alignment: .leading)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(system.displayName)
                            .font(RetroPlayFont.caption)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text("\(system.defaultCoreName) · \(gameCountText(gameCounts[SystemTab(system)] ?? 0))")
                            .font(RetroPlayFont.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: ready ? "checkmark.circle.fill" : "xmark.circle")
                        .foregroundStyle(ready ? Color.green : Color.secondary)
                        .accessibilityLabel(ready ? "Ready" : "Core not built in")
                }
                .padding(.vertical, 2)
            }
        } header: {
            sectionHeader("Systems")
        } footer: {
            sectionFooter("Every core runs without JIT: mupen64plus-next uses the cached interpreter, melonDS its interpreter, PPSSPP its IR interpreter.")
        }
        .listRowBackground(RetroPlayTheme.card(for: colorScheme))
    }

    private var aboutSection: some View {
        Section {
            LabeledContent {
                Text(Self.versionString)
                    .font(RetroPlayFont.caption)
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
                .font(RetroPlayFont.caption2)
                .lineSpacing(4)
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
        Text(title.uppercased())
            .font(RetroPlayFont.caption2)
            .foregroundStyle(RetroPlayTheme.secondaryText(for: colorScheme))
    }

    private func sectionFooter(_ text: String) -> some View {
        Text(text)
            .font(RetroPlayFont.caption2)
            .lineSpacing(3)
            .foregroundStyle(RetroPlayTheme.secondaryText(for: colorScheme))
    }

    private func helpRow(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(RetroPlayFont.caption2)
            Text(detail)
                .font(RetroPlayFont.caption2)
                .lineSpacing(3)
                .foregroundStyle(.secondary)
        }
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
            Text(title)
                .font(RetroPlayFont.caption)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
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
        }
    }
}
