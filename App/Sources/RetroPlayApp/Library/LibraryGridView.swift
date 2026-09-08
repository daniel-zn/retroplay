import UIKit
import SwiftUI
import RetroPlayCore

@available(iOS 18.0, *)
struct LibraryGridView<Header: View>: View {
    let games: [LibraryGame]
    let onSelect: (LibraryGame) -> Void
    let artworkProvider: (LibraryGame) -> UIImage?
    /// Custom large title drawn in the scroll content (system large titles stay blank on black chrome).
    var largeTitle: String? = nil
    /// Becomes true once the custom title has scrolled away; drives the inline nav title.
    var titleCollapsed: Binding<Bool>? = nil
    @ViewBuilder var header: () -> Header

    @Environment(\.colorScheme) private var colorScheme

    private let columns = [
        GridItem(.flexible(), spacing: 10, alignment: .top),
        GridItem(.flexible(), spacing: 10, alignment: .top),
        GridItem(.flexible(), spacing: 10, alignment: .top)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let largeTitle {
                    Text(largeTitle)
                        .font(.largeTitle.bold())
                        .foregroundStyle(RetroPlayTheme.primaryText(for: colorScheme))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.top, 2)
                        .padding(.bottom, 6)
                        .accessibilityAddTraits(.isHeader)
                }
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
            guard largeTitle != nil, let titleCollapsed else { return }
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
        largeTitle: String? = nil,
        titleCollapsed: Binding<Bool>? = nil
    ) {
        self.games = games
        self.onSelect = onSelect
        self.artworkProvider = artworkProvider
        self.largeTitle = largeTitle
        self.titleCollapsed = titleCollapsed
        self.header = { EmptyView() }
    }
}
