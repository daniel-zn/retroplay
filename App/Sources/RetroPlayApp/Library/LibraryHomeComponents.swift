// SPDX-License-Identifier: GPL-3.0-or-later
import UIKit
import SwiftUI
import RetroPlayCore

// MARK: - Activity

/// "Last played" per game. Play auto-saves a state on exit, so the newest save
/// state's date is when the game was last played — no extra bookkeeping needed.
enum LibraryActivity {
    static func lastPlayed(for games: [LibraryGame]) async -> [UUID: Date] {
        await Task.detached(priority: .utility) {
            var result: [UUID: Date] = [:]
            for game in games {
                if let date = SaveStateStore.newestEntry(system: game.systemID, gameID: game.id)?.modifiedAt {
                    result[game.id] = date
                }
            }
            return result
        }.value
    }
}

// MARK: - Sort

enum LibrarySort: String, CaseIterable, Identifiable {
    case recentlyPlayed
    case name
    case recentlyAdded

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recentlyPlayed: return "Recently Played"
        case .name: return "Name"
        case .recentlyAdded: return "Recently Added"
        }
    }

    var symbol: String {
        switch self {
        case .recentlyPlayed: return "clock"
        case .name: return "textformat"
        case .recentlyAdded: return "calendar.badge.plus"
        }
    }

    func sorted(_ games: [LibraryGame], lastPlayed: [UUID: Date]) -> [LibraryGame] {
        switch self {
        case .name:
            return games.sorted {
                $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
            }
        case .recentlyAdded:
            return games.sorted { $0.dateAdded > $1.dateAdded }
        case .recentlyPlayed:
            // Played games first (newest first), then the rest by date added.
            return games.sorted { a, b in
                switch (lastPlayed[a.id], lastPlayed[b.id]) {
                case let (x?, y?): return x > y
                case (.some, nil): return true
                case (nil, .some): return false
                case (nil, nil): return a.dateAdded > b.dateAdded
                }
            }
        }
    }
}

// MARK: - Layout

/// How the library shows its games (Settings → Library Layout). Search always uses the grid.
enum LibraryLayout: String, CaseIterable, Identifiable {
    case grid
    case coverFlow

    /// The user-defaults key it's remembered under.
    static let storageKey = "retroplay.libraryLayout"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .grid: return "Grid"
        case .coverFlow: return "Cover Flow"
        }
    }
}

struct SectionHeading: View {
    let title: String
    var trailing: String? = nil
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title.uppercased())
                .font(RetroPlayFont.titleFace(.caption))
                .foregroundStyle(RetroPlayTheme.primaryText(for: colorScheme))
                .retroPlayTitleGlitch(title)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if let trailing {
                Text(trailing)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .font(RetroPlayFont.caption2)
                    .foregroundStyle(RetroPlayTheme.secondaryText(for: colorScheme))
            }
        }
    }
}

// MARK: - Top bar

/// An icon button in the library's top bar, kept magenta whether the bar is clear (at the top)
/// or has its scrolled background.
struct LibraryTopBarButton: View {
    let title: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            LibraryTopBarIcon(symbol: symbol)
        }
        .accessibilityLabel(title)
        .accessibilityIdentifier("library.\(title.lowercased())")
    }
}

/// A top-bar icon: the plain symbol, laid out and spaced by the bar itself.
struct LibraryTopBarIcon: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            // System body size, as toolbar symbols normally are (and growing with Dynamic
            // Type), not the app's text font set as the environment default.
            .font(.body)
            // The bar's scrolled look recolours plain tinted items white; an explicit style
            // keeps the accent.
            .foregroundStyle(RetroPlayTheme.accent)
    }
}

/// The bottom bar's status while saves are found: a spinner and what it's doing.
struct LibraryImportStatus: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text(text)
                .font(RetroPlayFont.footnote)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }
}

/// The top bar's button while games copy in: a spinning progress symbol; tapped, a popover
/// lists each copy with its progress, how it ended, and a cancel.
struct LibraryImportsButton: View {
    @ObservedObject var imports: GameImports
    @Binding var showsStatus: Bool

    var body: some View {
        Button { showsStatus = true } label: {
            LibraryTopBarIcon(symbol: "progress.indicator")
                .symbolEffect(.variableColor.iterative, options: .repeating, isActive: imports.isRunning)
        }
        .accessibilityLabel("Imports")
        .accessibilityValue(summary)
        .accessibilityIdentifier("library.imports")
        .popover(isPresented: $showsStatus) {
            LibraryImportList(imports: imports)
                .presentationCompactAdaptation(.popover)
        }
    }

    private var summary: String {
        let running = imports.items.filter(\.isRunning).count
        return "Importing \(gameCountText(running))"
    }
}

/// Each game of this round of imports: its name, then its copy's progress or how it ended.
private struct LibraryImportList: View {
    @ObservedObject var imports: GameImports

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(imports.items) { item in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.name)
                                .lineLimit(2)
                            Text(detail(item))
                                .font(RetroPlayFont.footnote)
                                .monospacedDigit()
                                .foregroundStyle(isFailed(item) ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("library.imports.item")
                        Spacer(minLength: 0)
                        if item.isRunning {
                            Button("Cancel", systemImage: "xmark.circle.fill", role: .cancel) {
                                imports.cancel(item.id)
                            }
                            .labelStyle(.iconOnly)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Cancel \(item.name)")
                            .accessibilityIdentifier("library.imports.cancel")
                        }
                    }
                    if item.isRunning {
                        ProgressView(value: item.fraction ?? 0)
                            .accessibilityIdentifier("library.imports.progress")
                    }
                }
            }
        }
        .padding(20)
        .frame(minWidth: 280, maxWidth: 360)
    }

    private func isFailed(_ item: GameImports.Item) -> Bool {
        if case .failed = item.state { return true }
        return false
    }

    private func detail(_ item: GameImports.Item) -> String {
        switch item.state {
        case .waiting:
            return "Waiting"
        case .copying:
            let copied = item.copied.formatted(.byteCount(style: .file))
            guard let total = item.total, let fraction = item.fraction else { return copied }
            return "\(copied) of \(total.formatted(.byteCount(style: .file))) · \(fraction.formatted(.percent.precision(.fractionLength(0))))"
        case .done:
            return "Imported"
        case .failed(let reason):
            return reason
        case .cancelled:
            return "Cancelled"
        }
    }
}

/// "+": add games, or saves for games already in the library. A menu like the filter's, so
/// both open the same way from the same bar.
struct LibraryImportMenu: View {
    let onImportGames: () -> Void
    let onImportSaves: () -> Void

    var body: some View {
        Menu {
            Button(action: onImportGames) {
                Label {
                    Text("Games")
                    Text("ROMs and discs")
                } icon: {
                    Image(systemName: "gamecontroller")
                }
            }
            .accessibilityIdentifier("library.import.games")
            Button(action: onImportSaves) {
                Label {
                    Text("Saves")
                    Text("A folder to search for saves")
                } icon: {
                    Image(systemName: "sdcard")
                }
            }
            .accessibilityIdentifier("library.import.saves")
        } label: {
            LibraryTopBarIcon(symbol: "plus")
        }
        .menuOrder(.fixed)
        .accessibilityLabel("Import")
        .accessibilityIdentifier("library.import")
    }
}

/// The sort (first, so it's in reach however many systems follow) and the system filter, in
/// one menu behind a top-bar button. The filters list
/// their game counts and mark the one showing; L1 / R1 on a controller step through the same
/// list.
struct LibraryFilterMenu: View {
    @Binding var selection: SystemTab
    @Binding var sort: LibrarySort
    let tabs: [SystemTab]
    let counts: [SystemTab: Int]

    var body: some View {
        Menu {
            Section {
                Picker(selection: $sort) {
                    ForEach(LibrarySort.allCases) { option in
                        Label(option.title, systemImage: option.symbol).tag(option)
                    }
                } label: {
                    Text("Sort By")
                    Text(sort.title)
                }
                .pickerStyle(.menu)
            }
            Section {
                ForEach(tabs) { tab in
                    // Toggles: the menu marks the one showing, and the second line is the
                    // row's subtitle.
                    Toggle(isOn: binding(for: tab)) {
                        Text(tab == .all ? "All Games" : tab.systemID?.displayName ?? tab.title)
                        Text(gameCountText(counts[tab] ?? 0))
                    }
                }
            }
        } label: {
            LibraryTopBarIcon(
                symbol: selection == .all
                    ? "line.3.horizontal.decrease"
                    : "line.3.horizontal.decrease.circle.fill"
            )
        }
        .menuOrder(.fixed)
        .accessibilityLabel("Filter")
        .accessibilityIdentifier("library.filter")
        .accessibilityValue(
            "\(selection == .all ? "All games" : selection.title), sorted by \(sort.title)"
        )
    }

    private func binding(for tab: SystemTab) -> Binding<Bool> {
        Binding(
            get: { selection == tab },
            set: { on in
                guard on else { return }
                withAnimation(.easeOut(duration: 0.15)) { selection = tab }
            }
        )
    }
}

// MARK: - Empty states

/// First run: explain what to do and what's supported, with one big Import button.
struct LibraryOnboardingView: View {
    let onImport: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 22) {
            VStack(spacing: 14) {
                Image(systemName: "gamecontroller.fill")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(RetroPlayTheme.accent)
                    .symbolEffect(.pulse, options: .repeating)
                Text("INSERT GAME")
                    .font(RetroPlayFont.titleFace(.title3))
                    .foregroundStyle(RetroPlayTheme.primaryText(for: colorScheme))
                    .retroPlayTitleGlitch("INSERT GAME")
                Text("Import games you own from Files. RetroPlay picks the system and core for you.")
                    .font(RetroPlayFont.subheadline)
                    .lineSpacing(2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(RetroPlayTheme.secondaryText(for: colorScheme))
            }

            Button(action: onImport) {
                Label("Import Games", systemImage: "plus")
            }
            .buttonStyle(RetroPlayPrimaryButtonStyle())

            VStack(spacing: 0) {
                ForEach(Array(SystemID.allCases.enumerated()), id: \.element) { index, system in
                    if index > 0 { Divider().opacity(0.5) }
                    HStack(spacing: 10) {
                        SystemBadge(system: system)
                        Text(system.displayName)
                            .font(RetroPlayFont.footnote)
                            .foregroundStyle(RetroPlayTheme.primaryText(for: colorScheme))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Spacer(minLength: 8)
                        Text(Self.formats(system))
                            .font(RetroPlayFont.caption)
                            .foregroundStyle(RetroPlayTheme.secondaryText(for: colorScheme))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                    .padding(.vertical, 10)
                }
            }
            .padding(.horizontal, 14)
            .background(RetroPlayTheme.card(for: colorScheme), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            Text("No ROMs are included. Unzip archives before importing.")
                .font(RetroPlayFont.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(RetroPlayTheme.secondaryText(for: colorScheme))
        }
        .padding(24)
        .frame(maxWidth: 440)
        .frame(maxWidth: .infinity)
    }

    static func formats(_ system: SystemID) -> String {
        switch system {
        case .gba: return ".gba"
        case .n64: return ".z64 .n64 .v64"
        case .nds: return ".nds"
        case .psp: return ".iso .cso .chd .pbp"
        case .nes: return ".nes"
        case .snes: return ".sfc .smc"
        case .genesis: return ".md .gen .bin"
        case .atari7800: return ".a78"
        case .ps1: return ".chd .pbp .cue/.bin .exe"
        }
    }
}

/// A system filter with no games in it.
struct EmptyFilterView: View {
    let tab: SystemTab
    let onImport: () -> Void
    let onShowAll: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 14) {
            Text("NO \(tab.title) GAMES")
                .font(RetroPlayFont.titleFace(.headline))
                .foregroundStyle(RetroPlayTheme.primaryText(for: colorScheme))
                .retroPlayTitleGlitch("NO \(tab.title) GAMES")
            if let system = tab.systemID {
                Text("Import \(LibraryOnboardingView.formats(system)) files to play \(system.displayName) games.")
                    .font(RetroPlayFont.subheadline)
                    .lineSpacing(2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(RetroPlayTheme.secondaryText(for: colorScheme))
            }
            HStack(spacing: 10) {
                Button("Show All", action: onShowAll)
                    .buttonStyle(.glass)
                    .font(RetroPlayFont.callout)
                Button(action: onImport) {
                    Label("Import", systemImage: "plus")
                }
                .buttonStyle(RetroPlayPrimaryButtonStyle())
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity)
    }
}

/// "1 game" / "3 games" for labels and VoiceOver.
func gameCountText(_ count: Int) -> String {
    count == 1 ? "1 game" : "\(count) games"
}

// MARK: - Keyboard

extension View {
    /// A downward swipe hides the keyboard, for screens with nothing to scroll
    /// (scrolling screens use `.scrollDismissesKeyboard`).
    func keyboardSwipeDownDismiss(_ dismiss: @escaping () -> Void) -> some View {
        contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 20).onEnded { value in
                    if value.translation.height > 30,
                       value.translation.height > abs(value.translation.width) {
                        dismiss()
                    }
                }
            )
    }
}
