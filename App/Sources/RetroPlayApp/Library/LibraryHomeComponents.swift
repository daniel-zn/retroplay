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

// MARK: - Continue playing

/// Horizontal row of wide cards for the most recently played games.
@available(iOS 18.0, *)
struct ContinuePlayingRow: View {
    let games: [LibraryGame]
    let lastPlayed: [UUID: Date]
    let artworkProvider: (LibraryGame) -> UIImage?
    let onPlay: (LibraryGame) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeading(title: "Continue Playing")
                .padding(.horizontal, 16)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(games) { game in
                        Button {
                            onPlay(game)
                        } label: {
                            card(game)
                        }
                        .buttonStyle(RetroPlayPressStyle())
                        .accessibilityLabel("Continue \(game.displayName), \(game.systemID.displayName)")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 2)
            }
            .scrollClipDisabled()
        }
    }

    private func card(_ game: LibraryGame) -> some View {
        HStack(spacing: 12) {
            GameArtworkView(game: game, artwork: artworkProvider(game), cornerRadius: 10, labelTitleSize: 9)
                .frame(width: 72, height: 96)
            VStack(alignment: .leading, spacing: 8) {
                SystemBadge(system: game.systemID)
                Text(game.displayName)
                    .font(RetroPlayFont.caption)
                    .foregroundStyle(RetroPlayTheme.primaryText(for: colorScheme))
                    .lineLimit(2)
                    .lineSpacing(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 11, weight: .bold))
                    if let date = lastPlayed[game.id] {
                        Text(date.formatted(.relative(presentation: .named, unitsStyle: .abbreviated)))
                            .font(RetroPlayFont.caption2)
                            .lineLimit(1)
                    }
                }
                .foregroundStyle(RetroPlayTheme.accent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        // Fixed size at normal text sizes; wider and as tall as needed at accessibility sizes.
        .frame(width: dynamicTypeSize.isAccessibilitySize ? 320 : 270)
        .frame(minHeight: 116)
        .background(RetroPlayTheme.card(for: colorScheme), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(RetroPlayTheme.cardStroke(for: colorScheme), lineWidth: 1)
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
                    .font(RetroPlayFont.caption2)
                    .foregroundStyle(RetroPlayTheme.secondaryText(for: colorScheme))
            }
        }
    }
}

// MARK: - Filter + sort bar

@available(iOS 18.0, *)
struct LibraryFilterBar: View {
    @Binding var selection: SystemTab
    @Binding var sort: LibrarySort
    let counts: [SystemTab: Int]

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(SystemTab.allCases) { tab in
                        chip(tab)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 2)
            }
            sortMenu
                .padding(.trailing, 16)
        }
    }

    private func chip(_ tab: SystemTab) -> some View {
        let selected = selection == tab
        let count = counts[tab] ?? 0
        let tint = tab.systemID.map(RetroPlayTheme.systemTint) ?? RetroPlayTheme.accent
        return Button {
            withAnimation(.easeOut(duration: 0.15)) { selection = tab }
        } label: {
            HStack(spacing: 6) {
                if tab.systemID != nil {
                    Circle()
                        .fill(tint)
                        .frame(width: 7, height: 7)
                }
                Text(tab.title)
                    .font(RetroPlayFont.caption)
                Text("\(count)")
                    .font(RetroPlayFont.caption2)
                    .foregroundStyle(selected ? RetroPlayTheme.primaryText(for: colorScheme) : RetroPlayTheme.secondaryText(for: colorScheme))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .foregroundStyle(RetroPlayTheme.primaryText(for: colorScheme))
            .background {
                Capsule().fill(selected ? tint.opacity(0.28) : RetroPlayTheme.card(for: colorScheme))
            }
            .overlay {
                Capsule().strokeBorder(
                    selected ? tint : RetroPlayTheme.cardStroke(for: colorScheme),
                    lineWidth: 1
                )
            }
            .opacity(count == 0 && tab != .all && !selected ? 0.5 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(tab.title), \(gameCountText(count))")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sort", selection: $sort) {
                ForEach(LibrarySort.allCases) { option in
                    Label(option.title, systemImage: option.symbol).tag(option)
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(RetroPlayTheme.primaryText(for: colorScheme))
                .frame(width: 36, height: 36)
                .background(RetroPlayTheme.card(for: colorScheme), in: Circle())
                .overlay(Circle().strokeBorder(RetroPlayTheme.cardStroke(for: colorScheme), lineWidth: 1))
        }
        .accessibilityLabel("Sort: \(sort.title)")
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
                    .buttonStyle(.bordered)
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
