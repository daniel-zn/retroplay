// SPDX-License-Identifier: GPL-3.0-or-later
import UIKit
import SwiftUI
import RetroPlayCore

/// The library as one row of covers you swipe through (the PS Vita RetroFlow launcher's
/// look): the middle cover faces you, the others stand turned away in a stack on each
/// side, and the middle game's cover fills the screen behind, blurred.
@available(iOS 18.0, *)
struct LibraryCoverFlowView<Header: View>: View {
    let games: [LibraryGame]
    /// The system filter shown; each remembers its own middle game.
    let filter: SystemTab
    let onSelect: (LibraryGame) -> Void
    let artworkProvider: (LibraryGame) -> CoverArt?
    var onRequestDelete: ((LibraryGame) -> Void)?
    var lastPlayed: [UUID: Date] = [:]
    var missingGameIDs: Set<UUID> = []
    /// Drives the inline navigation title once the page scrolls (large text in landscape).
    var titleCollapsed: Binding<Bool>?
    /// Takes controller moves (left / right, A).
    var controllerNavigation = false
    @ViewBuilder let header: () -> Header

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @Environment(ControllerNavigator.self) private var navigator
    @AppStorage("retroplay.coverFlowFocus") private var memoryRaw = ""
    @State private var position = ScrollPosition(idType: UUID.self)
    /// The cover in the middle right now (moves while swiping).
    @State private var liveIndex = 0
    /// The game the carousel came to rest on (or was sent to): what's remembered, and what
    /// stays in the middle when the list changes.
    @State private var settledID: UUID?
    @State private var listKey: ListKey?
    @State private var headerHeight: CGFloat = 0
    @State private var captionHeight: CGFloat = 0

    private struct ListKey: Equatable {
        let filter: SystemTab
        let ids: [UUID]
    }

    private var focusedGame: LibraryGame? {
        games.isEmpty ? nil : games[min(liveIndex, games.count - 1)]
    }

    var body: some View {
        GeometryReader { outer in
            let metrics = CoverFlow.Metrics.fitting(
                width: outer.size.width,
                height: outer.size.height - headerHeight - captionHeight - 40
            )
            ScrollView(.vertical) {
                VStack(spacing: 0) {
                    header()
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { headerHeight = $0 }
                    if !games.isEmpty {
                        Spacer(minLength: 0)
                        carousel(metrics: metrics, width: outer.size.width)
                            .padding(.vertical, 12)
                        caption
                            .padding(.horizontal, 24)
                            .padding(.bottom, 16)
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { captionHeight = $0 }
                        Spacer(minLength: 0)
                    }
                }
                .frame(minHeight: outer.size.height)
            }
            // Scrolls only when large text leaves no room (landscape); otherwise it stays put.
            .scrollBounceBehavior(.basedOnSize)
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top > 28
            } action: { _, collapsed in
                if let titleCollapsed, titleCollapsed.wrappedValue != collapsed {
                    titleCollapsed.wrappedValue = collapsed
                }
            }
        }
        .background { backdrop }
        .onChange(of: ListKey(filter: filter, ids: games.map(\.id)), initial: true) { old, new in
            listChanged(from: listKey, to: new)
        }
        .onChange(of: navigator.event) { _, event in
            guard controllerNavigation, let event, event.context == .library else { return }
            handle(event.command)
        }
        #if DEBUG
        .task { await smokeScroll() }
        #endif
    }

    // MARK: Carousel

    private func carousel(metrics: CoverFlow.Metrics, width: CGFloat) -> some View {
        // The scroll view's coordinate space starts at its content margin, so the middle
        // of the viewport is half a step in.
        let middle = metrics.step / 2
        return ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(Array(games.enumerated()), id: \.element.id) { index, game in
                    coverButton(game, index: index, metrics: metrics)
                        .frame(width: metrics.step, height: metrics.coverSide)
                        // Covers nearer the middle stand in front.
                        .zIndex(-Double(abs(index - liveIndex)))
                        .visualEffect { content, proxy in
                            let frame = proxy.frame(in: .scrollView(axis: .horizontal))
                            let pose = metrics.pose(distance: frame.midX - middle)
                            return content
                                .rotation3DEffect(
                                    .degrees(pose.rotation),
                                    axis: (x: 0, y: 1, z: 0),
                                    perspective: 0.3
                                )
                                .scaleEffect(pose.scale)
                                .brightness(-pose.dimming)
                                .offset(x: pose.xShift)
                        }
                }
            }
            .scrollTargetLayout()
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
        .contentMargins(.horizontal, max(0, (width - metrics.step) / 2), for: .scrollContent)
        .scrollTargetBehavior(.viewAligned(limitBehavior: .never))
        .scrollPosition($position, anchor: .center)
        .onScrollGeometryChange(for: Int.self) { geometry in
            metrics.index(forOffset: geometry.contentOffset.x + geometry.contentInsets.leading, count: games.count)
        } action: { _, index in
            liveIndex = index
        }
        .onScrollPhaseChange { old, phase in
            // Only a swipe coming to rest; the row also goes idle when the list changes,
            // before it's been moved to the right game.
            if phase == .idle, old == .interacting || old == .decelerating {
                settle(at: liveIndex)
            }
        }
        .frame(height: metrics.coverSide)
        .sensoryFeedback(.selection, trigger: liveIndex)
    }

    private func coverButton(_ game: LibraryGame, index: Int, metrics: CoverFlow.Metrics) -> some View {
        let missing = missingGameIDs.contains(game.id)
        return Button {
            if index == liveIndex || voiceOverEnabled {
                onSelect(game)
            } else {
                move(to: index, animated: true)
            }
        } label: {
            CoverFlowCover(game: game, cover: artworkProvider(game), missing: missing)
                .frame(width: metrics.coverSide, height: metrics.coverSide)
        }
        .buttonStyle(RetroPlayPressStyle())
        .accessibilityLabel(
            missing
                ? "\(game.displayName), \(game.systemID.displayName), file missing"
                : "\(game.displayName), \(game.systemID.displayName)"
        )
        .accessibilityValue(lastPlayedText(game) ?? "")
        .accessibilityHint(missing ? "The game file was removed in Files" : "Starts the game")
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
        } preview: {
            // The cover facing front, whichever way it's turned in the row.
            CoverFlowCover(game: game, cover: artworkProvider(game), missing: missing, shadow: false)
                .frame(width: 260, height: 260)
        }
    }

    // MARK: Caption

    /// Title, system and last played for the middle game. Two title lines are always
    /// reserved so the covers don't jump as names change length.
    private var caption: some View {
        ZStack {
            if let game = focusedGame {
                VStack(spacing: 8) {
                    Text(game.displayName)
                        .font(RetroPlayFont.subheadline)
                        .foregroundStyle(RetroPlayTheme.primaryText(for: colorScheme))
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .lineLimit(2, reservesSpace: true)
                        .minimumScaleFactor(0.7)
                    HStack(spacing: 8) {
                        Text(game.systemID.displayName)
                            .foregroundStyle(RetroPlayTheme.systemTint(game.systemID))
                        Text("·")
                            .foregroundStyle(RetroPlayTheme.secondaryText(for: colorScheme))
                        Text(subtitle(game))
                            .foregroundStyle(
                                missingGameIDs.contains(game.id)
                                    ? Color.orange
                                    : RetroPlayTheme.secondaryText(for: colorScheme)
                            )
                    }
                    .font(RetroPlayFont.caption2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                }
                .id(game.id)
                .transition(.opacity)
            }
        }
        .frame(maxWidth: 560)
        .animation(.easeOut(duration: 0.18), value: focusedGame?.id)
        // VoiceOver reads the same on each cover.
        .accessibilityHidden(true)
    }

    private func lastPlayedText(_ game: LibraryGame) -> String? {
        lastPlayed[game.id].map {
            "Played " + $0.formatted(.relative(presentation: .named, unitsStyle: .abbreviated))
        }
    }

    private func subtitle(_ game: LibraryGame) -> String {
        if missingGameIDs.contains(game.id) { return "File missing" }
        return lastPlayedText(game) ?? "Not played yet"
    }

    // MARK: Backdrop

    /// The middle game's cover, blurred and dimmed, cross-fading as the row moves.
    private var backdrop: some View {
        ZStack {
            RetroPlayTheme.canvas(for: colorScheme)
            if let game = focusedGame {
                CoverFlowBackdropArt(game: game, cover: artworkProvider(game))
                    .id(game.id)
                    .transition(.opacity)
            }
            colorScheme == .dark ? Color.black.opacity(0.55) : Color.white.opacity(0.6)
        }
        .animation(.easeInOut(duration: 0.45), value: focusedGame?.id)
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    // MARK: Focus

    /// Brings `index` to the middle and remembers it.
    private func move(to index: Int, animated: Bool) {
        guard games.indices.contains(index) else { return }
        let id = games[index].id
        if animated {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                position.scrollTo(id: id, anchor: .center)
            }
        } else {
            position.scrollTo(id: id, anchor: .center)
        }
        settle(at: index)
    }

    private func settle(at index: Int) {
        guard games.indices.contains(index) else { return }
        let id = games[index].id
        settledID = id
        var memory = CoverFlow.Memory(raw: memoryRaw)
        if memory[filter.rawValue] != id {
            memory[filter.rawValue] = id
            memoryRaw = memory.raw
        }
    }

    /// A new filter, sort, import or delete: keep the middle game where it can be.
    private func listChanged(from old: ListKey?, to new: ListKey) {
        listKey = new
        let sameFilter = old?.filter == new.filter
        let target = CoverFlow.focus(
            in: new.ids,
            current: settledID,
            currentIndex: sameFilter ? settledID.flatMap { old?.ids.firstIndex(of: $0) } : nil,
            remembered: CoverFlow.Memory(raw: memoryRaw)[new.filter.rawValue]
        )
        guard let target, let index = new.ids.firstIndex(of: target) else { return }
        liveIndex = index
        // The new row is laid out over the next passes, and a scroll sent before it exists
        // is dropped: send it until the row has moved there.
        Task { @MainActor in
            for _ in 0..<10 {
                guard listKey == new else { return }
                move(to: index, animated: false)
                try? await Task.sleep(for: .milliseconds(50))
                if liveIndex == index { return }
            }
        }
    }

    /// D-pad / stick left and right move a cover; A plays the middle one.
    private func handle(_ command: ControllerNavCommand) {
        guard !games.isEmpty else { return }
        switch command {
        case .left: move(to: max(0, liveIndex - 1), animated: true)
        case .right: move(to: min(games.count - 1, liveIndex + 1), animated: true)
        case .confirm: onSelect(games[min(liveIndex, games.count - 1)])
        case .up, .down, .back, .previousPage, .nextPage: break
        }
    }

    #if DEBUG
    /// Screenshots (the Simulator can't swipe): `-RetroPlaySmokeCoverFlowIndex 4` brings the
    /// fifth cover to the middle; `-RetroPlaySmokeCoverFlowSlow YES` then glides on to the
    /// next one over eight seconds, to catch the row mid-swipe.
    private func smokeScroll() async {
        let defaults = UserDefaults.standard
        guard controllerNavigation, defaults.object(forKey: "RetroPlaySmokeCoverFlowIndex") != nil else { return }
        let index = defaults.integer(forKey: "RetroPlaySmokeCoverFlowIndex")
        try? await Task.sleep(for: .seconds(1.5))
        move(to: index, animated: true)
        guard defaults.bool(forKey: "RetroPlaySmokeCoverFlowSlow"), games.indices.contains(index + 1) else { return }
        try? await Task.sleep(for: .seconds(1))
        withAnimation(.linear(duration: 8)) {
            position.scrollTo(id: games[index + 1].id, anchor: .center)
        }
    }
    #endif
}

/// One cover in its square slot, standing on the bottom edge in its own shape.
@available(iOS 18.0, *)
private struct CoverFlowCover: View {
    let game: LibraryGame
    let cover: CoverArt?
    let missing: Bool
    var shadow = true

    @Environment(\.colorScheme) private var colorScheme

    private var aspect: CGFloat {
        if let cover, cover.isBoxArt, cover.image.size.height > 0 {
            return min(max(cover.image.size.width / cover.image.size.height, 0.5), 1.6)
        }
        return RetroPlayTheme.boxArtAspect(game.systemID)
    }

    var body: some View {
        Color.clear
            .overlay(alignment: .bottom) {
                GameArtworkView(
                    game: game,
                    artwork: cover?.image,
                    isBoxArt: cover?.isBoxArt ?? false,
                    cornerRadius: 10,
                    labelTitleSize: 16
                )
                .aspectRatio(aspect, contentMode: .fit)
                .overlay(alignment: .topLeading) {
                    if let cover, !cover.isBoxArt {
                        SystemBadge(system: game.systemID, style: .onArt)
                            .padding(6)
                    }
                }
                .opacity(missing ? 0.45 : 1)
                .overlay(alignment: .topTrailing) {
                    if missing {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white, .orange)
                            .padding(8)
                    }
                }
                .shadow(
                    color: .black.opacity(shadow ? (colorScheme == .dark ? 0.55 : 0.25) : 0),
                    radius: 14,
                    y: 8
                )
            }
            .contentShape(Rectangle())
            .accessibilityHidden(true)
    }
}

/// The blurred backdrop: a small copy of the cover, scaled up and softened (cheap to draw
/// at every swipe), or the system's colours for games without a cover.
@available(iOS 18.0, *)
private struct CoverFlowBackdropArt: View {
    let game: LibraryGame
    let cover: CoverArt?

    var body: some View {
        Color.clear
            .overlay {
                if let cover, let small = CoverFlowBackdropThumbnails.shared.thumbnail(of: cover.image, for: game.id) {
                    Image(uiImage: small)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFill()
                        .blur(radius: 24, opaque: true)
                        .saturation(1.2)
                } else {
                    LinearGradient(
                        colors: [
                            RetroPlayTheme.systemTint(game.systemID),
                            RetroPlayTheme.systemShade(game.systemID)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            }
            .clipped()
    }
}

/// Tiny copies of covers for the backdrop, so swiping doesn't blur full-size art.
@MainActor
private final class CoverFlowBackdropThumbnails {
    static let shared = CoverFlowBackdropThumbnails()
    private let cache = NSCache<NSString, UIImage>()

    init() { cache.countLimit = 64 }

    func thumbnail(of image: UIImage, for id: UUID) -> UIImage? {
        let key = "\(id.uuidString)-\(ObjectIdentifier(image).hashValue)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let longest = max(image.size.width, image.size.height)
        guard longest > 0 else { return nil }
        let scale = min(1, 48 / longest)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let small = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        cache.setObject(small, forKey: key)
        return small
    }
}
