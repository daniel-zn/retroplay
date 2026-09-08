import UIKit
import SwiftUI
import RetroPlayCore

@available(iOS 18.0, *)
struct LibraryGridView: View {
    let games: [LibraryGame]
    let onSelect: (LibraryGame) -> Void
    let artworkProvider: (LibraryGame) -> UIImage?

    @Environment(\.colorScheme) private var colorScheme

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        ScrollView {
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
            .padding(.vertical, 12)
        }
        .background(RetroPlayTheme.canvas(for: colorScheme))
    }
}
