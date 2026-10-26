// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI
import UIKit
import RetroPlayCore

extension RetailPackage.RGB {
    var color: Color { Color(red: red, green: green, blue: blue) }
}

/// A band of a system's package: its colour, pattern and the system's name.
struct PackageBandView: View {
    let band: RetailPackage.Band
    /// Turn the name to read down the band (a narrow spine band, or a leading front band).
    var verticalLabel = false

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                band.color.color
                pattern(size: size)
                label(size: size)
            }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func pattern(size: CGSize) -> some View {
        switch band.pattern {
        case .plain:
            EmptyView()
        case .gridLines:
            Canvas { context, size in
                var y: CGFloat = 2
                while y < size.height {
                    context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 0.7)),
                                 with: .color(.white.opacity(0.2)))
                    y += 3
                }
            }
        case .colorBars:
            let bars: [Color] = [
                Color(red: 0.85, green: 0.15, blue: 0.15), Color(red: 0.15, green: 0.6, blue: 0.25),
                Color(red: 0.15, green: 0.35, blue: 0.85), Color(red: 0.95, green: 0.75, blue: 0.1),
            ]
            let bar = min(size.width, size.height) * 0.16
            HStack(spacing: bar * 0.35) {
                ForEach(0..<bars.count, id: \.self) { bars[$0].frame(width: bar, height: bar) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: verticalLabel ? .bottom : .trailing)
            .padding(bar * 0.6)
        case .rule(let rule):
            Rectangle()
                .fill(rule.color)
                .frame(
                    width: band.edge == .leading ? 2 : nil,
                    height: band.edge == .leading ? nil : 2
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: ruleAlignment)
        }
    }

    /// The rule runs along the band's inner edge, where it meets the art.
    private var ruleAlignment: Alignment {
        switch band.edge {
        case .top: return .bottom
        case .bottom: return .top
        case .leading: return .trailing
        }
    }

    private func label(size: CGSize) -> some View {
        let across = verticalLabel ? size.width : size.height
        let along = verticalLabel ? size.height : size.width
        return Text(band.label)
            .font(.system(size: max(across * (verticalLabel ? 0.36 : 0.42), 6), weight: .heavy, design: .rounded))
            .tracking(across * 0.03)
            .foregroundStyle(band.color.isDark ? Color.white : Color(white: 0.15))
            .lineLimit(1)
            .minimumScaleFactor(0.3)
            .padding(.horizontal, across * (verticalLabel ? 0.12 : 0.25))
            .frame(width: along, height: across, alignment: band.pattern == .colorBars && !verticalLabel ? .leading : .center)
            .rotationEffect(.degrees(verticalLabel ? 90 : 0))
            .frame(width: size.width, height: size.height)
    }
}

/// The front of a game with no box art: its system's package (the band every front carries,
/// the frame round the art) with the game inside, so it still looks like the real box.
struct PackageFront<Art: View>: View {
    let package: RetailPackage
    @ViewBuilder let art: Art

    var body: some View {
        GeometryReader { geo in
            let band = package.frontBand
            let w = geo.size.width, h = geo.size.height
            let thick = band.edge == .leading ? w * band.thickness : h * band.thickness
            let inset = package.frontFrame == nil ? 0 : min(w, h) * 0.05
            let window = art
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .padding(inset)
            ZStack {
                (package.frontFrame ?? band.color).color
                switch band.edge {
                case .top:
                    VStack(spacing: 0) {
                        PackageBandView(band: band).frame(height: thick)
                        window.padding(.top, -inset)
                    }
                case .bottom:
                    VStack(spacing: 0) {
                        window.padding(.bottom, -inset)
                        PackageBandView(band: band).frame(height: thick)
                    }
                case .leading:
                    HStack(spacing: 0) {
                        PackageBandView(band: band, verticalLabel: true).frame(width: thick)
                        window.padding(.leading, -inset)
                    }
                }
            }
        }
    }
}

/// The side of a game's box as it turns in Cover Flow: its system's spine (the band with the
/// system's name, the case's colour) printed with the game's own title and, on a cardboard
/// box, a strip of its cover art.
struct PackageSpine: View {
    let system: SystemID
    let title: String
    let cover: CoverArt?
    /// The front's corner radius: the spine's front corners follow it round.
    var cornerRadius: CGFloat = 10

    var body: some View {
        let package = RetailPackage.of(system)
        let boxArt = cover.flatMap { $0.isBoxArt ? $0.image : nil }
        let edge = boxArt.flatMap { CoverEdgeColor.right(of: $0) }
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            // Tall enough for the system's name to read down it at the spine's width.
            let nameLength = CGFloat(package.spineBand.label.count) * w * 0.3 + w * 0.5
            let band = min(max(h * package.spineBand.thickness, nameLength), h * 0.3)
            let cardboard = package.material == .cardboard
            // A case's spine insert carries a block of the game's art at the foot.
            let insertArt = !cardboard && boxArt != nil ? h * 0.26 : 0
            let titleLength = max(h - band - insertArt, 1)
            let artBehindTitle = cardboard && boxArt != nil
            let lightTitle = artBehindTitle || package.spineTitleIsLight(edge: edge.map(\.rgb))
            let front = min(cornerRadius, w * 0.5)
            let back = min(cornerRadius * 0.6, w * 0.3)
            ZStack(alignment: .top) {
                if let boxArt, cardboard {
                    // The cover's own art, carried round from its right-hand edge.
                    Image(uiImage: boxArt)
                        .resizable()
                        .interpolation(.medium)
                        .scaledToFill()
                        .frame(width: w, height: h, alignment: .trailing)
                        .clipped()
                } else {
                    base(package, edge: edge)
                }
                VStack(spacing: 0) {
                    PackageBandView(band: package.spineBand, verticalLabel: true)
                        .frame(height: band)
                    Text(title)
                        .font(RetroPlayFont.sized(max(w * 0.4, 7), relativeTo: .caption))
                        .foregroundStyle(lightTitle ? Color.white : Color(white: 0.12))
                        .shadow(color: .black.opacity(artBehindTitle ? 0.8 : 0), radius: 1.5)
                        .lineLimit(1)
                        .minimumScaleFactor(0.45)
                        .padding(.horizontal, w * 0.35)
                        .frame(width: titleLength, height: w * (artBehindTitle ? 0.62 : 1), alignment: .leading)
                        // Printed on a band over the art, so it reads on any cover.
                        .background(.black.opacity(artBehindTitle ? 0.42 : 0))
                        .rotationEffect(.degrees(90))
                        .frame(width: w, height: titleLength)
                    if let boxArt, insertArt > 0 {
                        Image(uiImage: boxArt)
                            .resizable()
                            .interpolation(.medium)
                            .scaledToFill()
                            .frame(width: w, height: insertArt)
                            .clipped()
                    }
                }
            }
            .overlay {
                // The fold is rounded: light catches the front edge, the back curves away. A
                // plastic case's spine is rounder still.
                LinearGradient(
                    stops: cardboard
                        ? [.init(color: .white.opacity(0.24), location: 0),
                           .init(color: .white.opacity(0.04), location: 0.12),
                           .init(color: .clear, location: 0.55),
                           .init(color: .black.opacity(0.3), location: 1)]
                        : [.init(color: .black.opacity(0.22), location: 0),
                           .init(color: .white.opacity(0.26), location: 0.16),
                           .init(color: .clear, location: 0.45),
                           .init(color: .black.opacity(0.18), location: 0.8),
                           .init(color: .black.opacity(0.42), location: 1)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            }
            .clipShape(UnevenRoundedRectangle(
                topLeadingRadius: front,
                bottomLeadingRadius: front,
                bottomTrailingRadius: back,
                topTrailingRadius: back,
                style: .continuous
            ))
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func base(_ package: RetailPackage, edge: UIColor?) -> some View {
        if let color = package.spineColor {
            color.color
        } else if let edge {
            Color(uiColor: edge)
        } else {
            LinearGradient(
                colors: [RetroPlayTheme.systemTint(system).opacity(0.9), RetroPlayTheme.systemShade(system)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

/// The top of a game's box, seen as the row looks down on it: on a cardboard box the cover's
/// art runs over the top from its top edge; a case is its plastic. Drawn back edge up.
struct PackageTop: View {
    let system: SystemID
    let cover: CoverArt?
    /// The front's corner radius: the top's front corners follow it round.
    var cornerRadius: CGFloat = 10

    var body: some View {
        let package = RetailPackage.of(system)
        let boxArt = cover.flatMap { $0.isBoxArt ? $0.image : nil }
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let front = min(cornerRadius, h * 0.5)
            let back = min(cornerRadius * 0.6, h * 0.3)
            ZStack {
                if let boxArt, package.material == .cardboard {
                    Image(uiImage: boxArt)
                        .resizable()
                        .interpolation(.medium)
                        .scaledToFill()
                        .frame(width: w, height: h, alignment: .top)
                        .clipped()
                } else if let color = package.spineColor {
                    color.color
                } else if let boxArt, let edge = CoverEdgeColor.right(of: boxArt) {
                    Color(uiColor: edge)
                } else {
                    RetroPlayTheme.systemTint(system).opacity(0.9)
                }
            }
            .overlay {
                // The front edge catches the light; the top falls away towards the back.
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.28), location: 0),
                        .init(color: .clear, location: 0.6),
                        .init(color: .white.opacity(package.material == .cardboard ? 0.18 : 0.26), location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .clipShape(UnevenRoundedRectangle(
                topLeadingRadius: back,
                bottomLeadingRadius: front,
                bottomTrailingRadius: front,
                topTrailingRadius: back,
                style: .continuous
            ))
        }
        .accessibilityHidden(true)
    }
}

private extension UIColor {
    var rgb: RetailPackage.RGB {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return RetailPackage.RGB(Double(r), Double(g), Double(b))
    }
}

/// The average colour down a cover's right edge, so a box's side carries on from its front.
/// Worked out once per picture.
@MainActor
enum CoverEdgeColor {
    private static let cache = NSCache<UIImage, UIColor>()

    private static let topCache = NSCache<UIImage, UIColor>()

    static func right(of image: UIImage) -> UIColor? {
        if let known = cache.object(forKey: image) { return known }
        guard let cg = image.cgImage, cg.width > 4, cg.height > 0 else { return nil }
        let strip = max(cg.width / 25, 1)
        guard let color = average(cg, CGRect(x: cg.width - strip, y: 0, width: strip, height: cg.height)) else {
            return nil
        }
        cache.setObject(color, forKey: image)
        return color
    }

    /// The average colour along a cover's top edge.
    static func top(of image: UIImage) -> UIColor? {
        if let known = topCache.object(forKey: image) { return known }
        guard let cg = image.cgImage, cg.width > 0, cg.height > 4 else { return nil }
        let strip = max(cg.height / 25, 1)
        guard let color = average(cg, CGRect(x: 0, y: 0, width: cg.width, height: strip)) else { return nil }
        topCache.setObject(color, forKey: image)
        return color
    }

    private static func average(_ cg: CGImage, _ rect: CGRect) -> UIColor? {
        guard let edge = cg.cropping(to: rect) else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        let drawn = pixel.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(
                data: bytes.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.interpolationQuality = .medium
            context.draw(edge, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        guard drawn else { return nil }
        // A touch darker than the edge: the side faces away from the light.
        return UIColor(
            red: CGFloat(pixel[0]) / 255 * 0.9,
            green: CGFloat(pixel[1]) / 255 * 0.9,
            blue: CGFloat(pixel[2]) / 255 * 0.9,
            alpha: 1
        )
    }
}

#if DEBUG
/// `-RetroPlaySmokePackages YES`: every system's generic front and spine, flat, for
/// screenshots.
struct RetailPackageGallery: View {
    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 12)], spacing: 16) {
                ForEach(SystemID.allCases) { system in
                    let game = LibraryGame(displayName: "Sample Game Title", systemID: system, relativePath: "sample")
                    HStack(alignment: .bottom, spacing: 2) {
                        GameArtworkView(game: game, cornerRadius: 6, labelTitleSize: 11)
                            .aspectRatio(RetroPlayTheme.boxArtAspect(system), contentMode: .fit)
                            .frame(width: 100)
                        PackageSpine(system: system, title: game.displayName, cover: nil)
                            .frame(width: 100 * CoverFlow.boxDepth(system) * 2.5,
                                   height: 100 / RetroPlayTheme.boxArtAspect(system))
                    }
                }
            }
            .padding(16)
        }
        .background(Color.black)
    }
}
#endif
