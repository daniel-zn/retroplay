// SPDX-License-Identifier: GPL-3.0-or-later
import UIKit
import SwiftUI
import RetroPlayCore

@available(iOS 18.0, *)
struct LibraryGridView<Header: View>: View {
    let games: [LibraryGame]
    let onSelect: (LibraryGame) -> Void
    let artworkProvider: (LibraryGame) -> CoverArt?
    /// When non-nil, long-press offers Delete (confirmation lives on the caller).
    var onRequestDelete: ((LibraryGame) -> Void)? = nil
    /// When non-nil, drives inline nav collapse once scroll offset exceeds threshold.
    let titleCollapsed: Binding<Bool>?
    /// Last played (newest save state) per game, for the tile subtitle.
    var lastPlayed: [UUID: Date] = [:]
    /// Rows whose ROM was removed in Files; drawn dimmed with a warning mark.
    var missingGameIDs: Set<UUID> = []
    /// Takes controller moves (the main library, not search results).
    var controllerNavigation = false
    let header: () -> Header

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(ControllerNavigator.self) private var navigator
    /// The controller cursor (nil until the first controller move).
    @State private var focusedIndex: Int?
    @State private var gridWidth: CGFloat = 0

    /// Three across on a phone (more in landscape); two at accessibility text sizes, where a
    /// narrow tile would leave only a few letters per line.
    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: tileMinimum, maximum: 240), spacing: 12, alignment: .top)]
    }

    private var tileMinimum: CGFloat { dynamicTypeSize.isAccessibilitySize ? 150 : 100 }

    /// Tiles per row, as the adaptive grid lays them out.
    private var columnCount: Int {
        max(1, Int((gridWidth + 12) / (tileMinimum + 12)))
    }

    init(
        games: [LibraryGame],
        onSelect: @escaping (LibraryGame) -> Void,
        artworkProvider: @escaping (LibraryGame) -> CoverArt?,
        onRequestDelete: ((LibraryGame) -> Void)? = nil,
        titleCollapsed: Binding<Bool>? = nil,
        lastPlayed: [UUID: Date] = [:],
        missingGameIDs: Set<UUID> = [],
        controllerNavigation: Bool = false,
        @ViewBuilder header: @escaping () -> Header
    ) {
        self.controllerNavigation = controllerNavigation
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
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header()
                LazyVGrid(columns: columns, spacing: 18) {
                    ForEach(Array(games.enumerated()), id: \.element.id) { index, game in
                        Button {
                            onSelect(game)
                        } label: {
                            GameTileView(
                                game: game,
                                cover: artworkProvider(game),
                                lastPlayed: lastPlayed[game.id]
                            )
                            .opacity(missingGameIDs.contains(game.id) ? 0.45 : 1)
                            .controllerFocusRing(focusedIndex == index, cornerRadius: 8)
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
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { gridWidth = $0 }
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
        .onChange(of: navigator.event) { _, event in
            guard controllerNavigation, let event, event.context == .library else { return }
            handle(event.command)
        }
        .onChange(of: focusedIndex) { _, index in
            guard let index, games.indices.contains(index) else { return }
            withAnimation(.easeOut(duration: 0.15)) {
                proxy.scrollTo(games[index].id, anchor: .center)
            }
        }
        .onChange(of: games.map(\.id)) { _, ids in
            if let index = focusedIndex { focusedIndex = ids.isEmpty ? nil : min(index, ids.count - 1) }
        }
        .onChange(of: navigator.isConnected) { _, connected in
            if !connected { focusedIndex = nil }
        }
        #if DEBUG
        // Screenshots of the collapsed title bar: `-RetroPlaySmokeScrolled YES`.
        .task {
            guard controllerNavigation, UserDefaults.standard.bool(forKey: "RetroPlaySmokeScrolled"),
                  let last = games.last else { return }
            try? await Task.sleep(for: .seconds(2))
            proxy.scrollTo(last.id, anchor: .bottom)
        }
        #endif
        }
    }
}

@available(iOS 18.0, *)
extension LibraryGridView {
    /// D-pad / stick move the cursor a tile (a row up or down); A plays the game under it.
    /// The first move only shows the cursor.
    private func handle(_ command: ControllerNavCommand) {
        guard !games.isEmpty else { return }
        guard let index = focusedIndex else {
            if command != .back { focusedIndex = 0 }
            return
        }
        switch command {
        case .left: focusedIndex = max(0, index - 1)
        case .right: focusedIndex = min(games.count - 1, index + 1)
        case .up: focusedIndex = index - columnCount >= 0 ? index - columnCount : index
        case .down: focusedIndex = min(games.count - 1, index + columnCount)
        case .confirm: onSelect(games[index])
        case .back, .previousPage, .nextPage: break
        }
    }
}

@available(iOS 18.0, *)
extension LibraryGridView where Header == EmptyView {
    init(
        games: [LibraryGame],
        onSelect: @escaping (LibraryGame) -> Void,
        artworkProvider: @escaping (LibraryGame) -> CoverArt?,
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
struct LibraryTileDeleteAccessibilityAction: ViewModifier {
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
