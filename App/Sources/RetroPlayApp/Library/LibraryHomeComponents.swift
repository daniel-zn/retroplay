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

@available(iOS 18.0, *)
struct SectionHeading: View {
    let title: String
    var trailing: String? = nil
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title.uppercased())
                .font(RetroPlayFont.caption)
                .foregroundStyle(RetroPlayTheme.primaryText(for: colorScheme))
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
@available(iOS 18.0, *)
struct LibraryTopBarButton: View {
    let title: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            LibraryTopBarIcon(title: title, symbol: symbol)
        }
        .accessibilityLabel(title)
    }
}

@available(iOS 18.0, *)
struct LibraryTopBarIcon: View {
    let title: String
    let symbol: String

    var body: some View {
        Label(title, systemImage: symbol)
            .labelStyle(.iconOnly)
            // The bar's scrolled look recolours plain tinted items white; an explicit style
            // keeps the accent.
            .foregroundStyle(RetroPlayTheme.accent)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .retroPlayGlassChrome()
    }
}

/// The sort (first, so it's in reach however many systems follow) and the system filter, in
/// one menu behind a top-bar button. The filters list
/// their game counts and mark the one showing; L1 / R1 on a controller step through the same
/// list.
@available(iOS 18.0, *)
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
                title: "Filter",
                symbol: selection == .all
                    ? "line.3.horizontal.decrease"
                    : "line.3.horizontal.decrease.circle.fill"
            )
        }
        .menuOrder(.fixed)
        .accessibilityLabel("Filter")
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
@available(iOS 18.0, *)
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
                    .font(RetroPlayFont.title3)
                    .foregroundStyle(RetroPlayTheme.primaryText(for: colorScheme))
                Text("Import games you own from Files. RetroPlay picks the system and core for you.")
                    .font(RetroPlayFont.caption)
                    .lineSpacing(4)
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
                            .font(RetroPlayFont.caption2)
                            .foregroundStyle(RetroPlayTheme.primaryText(for: colorScheme))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Spacer(minLength: 8)
                        Text(Self.formats(system))
                            .font(RetroPlayFont.caption2)
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
                .font(RetroPlayFont.caption2)
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
@available(iOS 18.0, *)
struct EmptyFilterView: View {
    let tab: SystemTab
    let onImport: () -> Void
    let onShowAll: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 14) {
            Text("NO \(tab.title) GAMES")
                .font(RetroPlayFont.subheadline)
                .foregroundStyle(RetroPlayTheme.primaryText(for: colorScheme))
            if let system = tab.systemID {
                Text("Import \(LibraryOnboardingView.formats(system)) files to play \(system.displayName) games.")
                    .font(RetroPlayFont.caption2)
                    .lineSpacing(3)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(RetroPlayTheme.secondaryText(for: colorScheme))
            }
            HStack(spacing: 10) {
                Button("Show All", action: onShowAll)
                    .glassButton()
                    .font(RetroPlayFont.caption)
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
