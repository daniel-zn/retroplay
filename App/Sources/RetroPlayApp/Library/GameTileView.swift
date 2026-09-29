// SPDX-License-Identifier: GPL-3.0-or-later
import UIKit
import SwiftUI
import RetroPlayCore

/// Cover art, or — for the many games without one — a cartridge-style label:
/// system-coloured gradient, scanlines, and the game's name in the pixel face.
@available(iOS 18.0, *)
struct GameArtworkView: View {
    let game: LibraryGame
    var artwork: UIImage?
    var cornerRadius: CGFloat = 12
    /// Label title size; tiles use the default, wide cards go larger.
    var labelTitleSize: CGFloat = 13

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Color.clear
            .overlay {
                if let artwork {
                    artworkImage(artwork)
                } else {
                    labelArt
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(RetroPlayTheme.cardStroke(for: colorScheme), lineWidth: 1)
            }
    }

    /// Disc and cartridge icons are rarely the tile's shape (PSP ICON0 is 144×80, the DS
    /// banner icon 32×32), so show the whole icon over a blurred fill of itself instead of
    /// cropping it. Tiny pixel-art icons scale with nearest-neighbour so they stay crisp.
    private func artworkImage(_ image: UIImage) -> some View {
        let pixels = max(image.size.width, image.size.height) * image.scale
        let interpolation: Image.Interpolation = pixels <= 64 ? .none : .medium
        // The fitted icon sets the size; the fill sits behind it as a background so it
        // can't grow the tile (in a ZStack it would, and the "fit" would crop again).
        return Image(uiImage: image)
            .resizable()
            .interpolation(interpolation)
            .scaledToFit()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(interpolation)
                    .scaledToFill()
                    .blur(radius: 14, opaque: true)
                    .opacity(0.8)
                    .accessibilityHidden(true)
            }
    }

    private var labelArt: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(
                colors: [
                    RetroPlayTheme.systemTint(game.systemID).opacity(0.9),
                    RetroPlayTheme.systemShade(game.systemID)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Canvas { context, size in
                // CRT scanlines.
                var y: CGFloat = 0
                while y < size.height {
                    context.fill(
                        Path(CGRect(x: 0, y: y, width: size.width, height: 1)),
                        with: .color(.black.opacity(0.14))
                    )
                    y += 3
                }
            }
            VStack(alignment: .leading, spacing: 0) {
                SystemBadge(system: game.systemID, style: .onArt)
                Spacer(minLength: 4)
                Text(game.displayName)
                    .font(RetroPlayFont.sized(labelTitleSize + 2, relativeTo: .caption))
                    .foregroundStyle(.white)
                    .lineSpacing(3)
                    .lineLimit(4)
                    .minimumScaleFactor(0.6)
                    .multilineTextAlignment(.leading)
                    .shadow(color: .black.opacity(0.5), radius: 0, x: 1, y: 1)
            }
            .padding(8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

/// Small system pill ("GBA", "N64", …).
@available(iOS 18.0, *)
struct SystemBadge: View {
    enum Style {
        /// Dark translucent chip for use over art.
        case onArt
        /// Tinted chip for use on plain backgrounds.
        case tinted
    }

    let system: SystemID
    var style: Style = .tinted

    var body: some View {
        Text(RetroPlayTheme.shortName(system))
            .font(RetroPlayFont.sized(10, relativeTo: .caption2))
            .foregroundStyle(style == .onArt ? .white : RetroPlayTheme.systemTint(system))
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background {
                Capsule().fill(
                    style == .onArt
                        ? Color.black.opacity(0.35)
                        : RetroPlayTheme.systemTint(system).opacity(0.16)
                )
            }
            .accessibilityHidden(true)
    }
}

@available(iOS 18.0, *)
struct GameTileView: View {
    let game: LibraryGame
    var artwork: UIImage?
    /// Most recent save state, used as "last played" (Play auto-saves on exit).
    var lastPlayed: Date?

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GameArtworkView(game: game, artwork: artwork)
                .aspectRatio(3 / 4, contentMode: .fit)
                .overlay(alignment: .topLeading) {
                    if artwork != nil {
                        SystemBadge(system: game.systemID, style: .onArt)
                            .padding(6)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if lastPlayed != nil {
                        resumeMark
                    }
                }
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.4 : 0.12), radius: 6, y: 3)

            Text(game.displayName)
                .font(RetroPlayFont.caption)
                .foregroundStyle(RetroPlayTheme.primaryText(for: colorScheme))
                .lineLimit(2)
                .lineSpacing(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(subtitle)
                .font(RetroPlayFont.caption2)
                .foregroundStyle(RetroPlayTheme.secondaryText(for: colorScheme))
                .lineLimit(1)
        }
        .contentShape(Rectangle())
        .accessibilityHidden(true)
    }

    private var subtitle: String {
        if let lastPlayed {
            return lastPlayed.formatted(.relative(presentation: .named, unitsStyle: .abbreviated))
        }
        return RetroPlayTheme.shortName(game.systemID)
    }

    /// "Resumes where you left off" marker.
    private var resumeMark: some View {
        Image(systemName: "play.fill")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 24, height: 24)
            .background(RetroPlayTheme.accent, in: Circle())
            .overlay(Circle().strokeBorder(.black.opacity(0.35), lineWidth: 1))
            .padding(6)
    }
}
