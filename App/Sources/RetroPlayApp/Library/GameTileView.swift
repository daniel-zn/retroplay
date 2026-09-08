import UIKit
import SwiftUI
import RetroPlayCore

@available(iOS 18.0, *)
struct GameTileView: View {
    let game: LibraryGame
    var artwork: UIImage?

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                RetroPlayTheme.systemTint(game.systemID).opacity(0.55),
                                RetroPlayTheme.card(for: colorScheme)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                if let artwork {
                    Image(uiImage: artwork)
                        .resizable()
                        .scaledToFill()
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else {
                    VStack(spacing: 6) {
                        Image(systemName: RetroPlayTheme.systemSymbol(game.systemID))
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.92))
                        Text(shortSystemLabel(game.systemID))
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.white.opacity(0.75))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .padding(6)
                }
            }
            .aspectRatio(3 / 4, contentMode: .fit)
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(RetroPlayTheme.cardStroke(for: colorScheme), lineWidth: 1)
            }

            Text(game.displayName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(RetroPlayTheme.primaryText(for: colorScheme))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, minHeight: 32, alignment: .topLeading)
            Text(game.systemID.defaultCoreName)
                .font(.caption2)
                .foregroundStyle(RetroPlayTheme.secondaryText(for: colorScheme))
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(game.displayName), \(game.systemID.displayName)")
    }

    private func shortSystemLabel(_ id: SystemID) -> String {
        switch id {
        case .gba: return "GBA"
        case .n64: return "N64"
        case .nds: return "NDS"
        case .psp: return "PSP"
        }
    }
}
