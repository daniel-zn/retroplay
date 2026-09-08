import UIKit
import SwiftUI
import RetroPlayCore

@available(iOS 18.0, *)
struct LibraryGridView<Header: View>: View {
    let games: [LibraryGame]
    let onSelect: (LibraryGame) -> Void
    let artworkProvider: (LibraryGame) -> UIImage?
    /// When non-nil, drives inline nav collapse once scroll offset exceeds threshold.
    let titleCollapsed: Binding<Bool>?
    let header: () -> Header

    @Environment(\.colorScheme) private var colorScheme

    private let columns = [
        GridItem(.flexible(), spacing: 10, alignment: .top),
        GridItem(.flexible(), spacing: 10, alignment: .top),
        GridItem(.flexible(), spacing: 10, alignment: .top)
    ]

    init(
        games: [LibraryGame],
        onSelect: @escaping (LibraryGame) -> Void,
        artworkProvider: @escaping (LibraryGame) -> UIImage?,
        titleCollapsed: Binding<Bool>? = nil,
        @ViewBuilder header: @escaping () -> Header
    ) {
        self.games = games
        self.onSelect = onSelect
        self.artworkProvider = artworkProvider
        self.titleCollapsed = titleCollapsed
        self.header = header
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header()
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(games) { game in
                        Button {
                            onSelect(game)
                        } label: {
                            GameTileView(game: game, artwork: artworkProvider(game))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
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
        titleCollapsed: Binding<Bool>? = nil
    ) {
        self.init(
            games: games,
            onSelect: onSelect,
            artworkProvider: artworkProvider,
            titleCollapsed: titleCollapsed,
            header: { EmptyView() }
        )
    }
}
