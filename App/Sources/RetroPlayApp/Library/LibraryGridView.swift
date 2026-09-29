// SPDX-License-Identifier: GPL-3.0-or-later
import UIKit
import SwiftUI
import RetroPlayCore

@available(iOS 18.0, *)
struct LibraryGridView<Header: View>: View {
    let games: [LibraryGame]
    let onSelect: (LibraryGame) -> Void
    let artworkProvider: (LibraryGame) -> UIImage?
    /// When non-nil, long-press offers Delete (confirmation lives on the caller).
    var onRequestDelete: ((LibraryGame) -> Void)? = nil
    /// When non-nil, drives inline nav collapse once scroll offset exceeds threshold.
    let titleCollapsed: Binding<Bool>?
    /// Last played (newest save state) per game, for the tile subtitle and resume mark.
    var lastPlayed: [UUID: Date] = [:]
    /// Rows whose ROM was removed in Files; drawn dimmed with a warning mark.
    var missingGameIDs: Set<UUID> = []
    let header: () -> Header

    @Environment(\.colorScheme) private var colorScheme

    /// Three across on a phone, more on iPad / landscape.
    private let columns = [
        GridItem(.adaptive(minimum: 100, maximum: 170), spacing: 12, alignment: .top)
    ]

    init(
        games: [LibraryGame],
        onSelect: @escaping (LibraryGame) -> Void,
        artworkProvider: @escaping (LibraryGame) -> UIImage?,
        onRequestDelete: ((LibraryGame) -> Void)? = nil,
        titleCollapsed: Binding<Bool>? = nil,
        lastPlayed: [UUID: Date] = [:],
        missingGameIDs: Set<UUID> = [],
        @ViewBuilder header: @escaping () -> Header
    ) {
        self.lastPlayed = lastPlayed
        self.missingGameIDs = missingGameIDs
        self.games = games
        self.onSelect = onSelect
        self.artworkProvider = artworkProvider
        self.onRequestDelete = onRequestDelete
        self.titleCollapsed = titleCollapsed
        self.header = header
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header()
                LazyVGrid(columns: columns, spacing: 18) {
                    ForEach(games) { game in
                        Button {
                            onSelect(game)
                        } label: {
                            GameTileView(
                                game: game,
                                artwork: artworkProvider(game),
                                lastPlayed: lastPlayed[game.id]
                            )
                            .opacity(missingGameIDs.contains(game.id) ? 0.45 : 1)
                            .overlay(alignment: .topTrailing) {
                                if missingGameIDs.contains(game.id) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(.white, .orange)
                                        .padding(6)
                                        .accessibilityHidden(true)
                                }
                            }
                        }
                        .buttonStyle(RetroPlayPressStyle())
                        .accessibilityLabel(
                            missingGameIDs.contains(game.id)
                                ? "\(game.displayName), \(game.systemID.displayName), file missing"
                                : "\(game.displayName), \(game.systemID.displayName)"
                        )
                        .accessibilityHint(missingGameIDs.contains(game.id) ? "The game file was removed in Files" : "Starts the game")
                        .modifier(LibraryTileDeleteAccessibilityAction(game: game, onRequestDelete: onRequestDelete))
                        .contextMenu {
                            Button {
                                onSelect(game)
                            } label: {
                                Label(lastPlayed[game.id] == nil ? "Play" : "Continue", systemImage: "play.fill")
                            }
                            if onRequestDelete != nil {
                                Button(role: .destructive) {
                                    onRequestDelete?(game)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
                .padding(.top, 4)
            }
        }
        .background(RetroPlayTheme.canvas(for: colorScheme))
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top
        } action: { _, offset in
            guard let titleCollapsed else { return }
            let collapsed = offset > 28
            if titleCollapsed.wrappedValue != collapsed {
                titleCollapsed.wrappedValue = collapsed
            }
        }
    }
}

@available(iOS 18.0, *)
extension LibraryGridView where Header == EmptyView {
    init(
        games: [LibraryGame],
        onSelect: @escaping (LibraryGame) -> Void,
        artworkProvider: @escaping (LibraryGame) -> UIImage?,
        onRequestDelete: ((LibraryGame) -> Void)? = nil,
        titleCollapsed: Binding<Bool>? = nil,
        lastPlayed: [UUID: Date] = [:],
        missingGameIDs: Set<UUID> = []
    ) {
        self.init(
            games: games,
            onSelect: onSelect,
            artworkProvider: artworkProvider,
            onRequestDelete: onRequestDelete,
            titleCollapsed: titleCollapsed,
            lastPlayed: lastPlayed,
            missingGameIDs: missingGameIDs,
            header: { EmptyView() }
        )
    }
}

@available(iOS 18.0, *)
private struct LibraryTileDeleteAccessibilityAction: ViewModifier {
    let game: LibraryGame
    let onRequestDelete: ((LibraryGame) -> Void)?

    func body(content: Content) -> some View {
        if let onRequestDelete {
            content.accessibilityAction(named: "Delete") {
                onRequestDelete(game)
            }
        } else {
            content
        }
    }
}
