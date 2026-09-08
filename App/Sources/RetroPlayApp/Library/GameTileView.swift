import UIKit
import SwiftUI
import RetroPlayCore

@available(iOS 18.0, *)
struct GameTileView: View {
    let game: LibraryGame
    var artwork: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                RetroPlayTheme.systemTint(game.systemID).opacity(0.55),
                                RetroPlayTheme.card
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                if let artwork {
                    Image(uiImage: artwork)
                        .resizable()
                        .scaledToFill()
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: RetroPlayTheme.systemSymbol(game.systemID))
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.92))
                        Text(game.systemID.displayName)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(1)
                    }
                    .padding(8)
                }
            }
            .aspectRatio(3 / 4, contentMode: .fit)
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(RetroPlayTheme.cardStroke, lineWidth: 1)
            }

            Text(game.displayName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Text(game.systemID.defaultCoreName)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.45))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(game.displayName), \(game.systemID.displayName)")
    }
}
