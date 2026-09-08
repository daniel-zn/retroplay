import UIKit
import SwiftUI
import RetroPlayCore

@available(iOS 18.0, *)
struct LibraryGridView<Header: View>: View {
    let games: [LibraryGame]
    let onSelect: (LibraryGame) -> Void
    let artworkProvider: (LibraryGame) -> UIImage?
    @ViewBuilder var header: () -> Header

    @Environment(\.colorScheme) private var colorScheme

    private let columns = [
        GridItem(.flexible(), spacing: 10, alignment: .top),
        GridItem(.flexible(), spacing: 10, alignment: .top),
        GridItem(.flexible(), spacing: 10, alignment: .top)
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
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
    }
}

@available(iOS 18.0, *)
extension LibraryGridView where Header == EmptyView {
    init(
        games: [LibraryGame],
        onSelect: @escaping (LibraryGame) -> Void,
        artworkProvider: @escaping (LibraryGame) -> UIImage?
    ) {
        self.games = games
        self.onSelect = onSelect
        self.artworkProvider = artworkProvider
        self.header = { EmptyView() }
    }
}
