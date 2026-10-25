// SPDX-License-Identifier: GPL-3.0-or-later
import UIKit
import SwiftUI
import RetroPlayCore

/// The library as one row of covers you swipe through (the PS Vita RetroFlow launcher's
/// look): the middle cover faces you, the others stand turned away in a stack on each
/// side, on the same plain background as the grid.
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
    /// Where the row is right now, for the snapping to know where a swipe was let go.
    @State private var tracker = CoverFlowScrollTracker()
    @Environment(\.verticalSizeClass) private var verticalSizeClass

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
                height: outer.size.height - headerHeight - captionHeight - 32
            )
            ScrollView(.vertical) {
                VStack(spacing: 0) {
                    header()
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { headerHeight = $0 }
                    if !games.isEmpty {
                        Spacer(minLength: 0)
                        carousel(metrics: metrics, width: outer.size.width)
                            .padding(.top, 8)
                            .padding(.bottom, 12)
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
        .background(RetroPlayTheme.canvas(for: colorScheme).ignoresSafeArea())
        #if DEBUG
        // UI tests read which cover is in the middle.
        .overlay(alignment: .bottomLeading) {
            Text("\(liveIndex)")
                .font(.system(size: 2))
                .opacity(0.02)
                .accessibilityIdentifier("coverFlow.position")
                .accessibilityValue("\(liveIndex)")
        }
        #endif
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
        // A swipe moves the row a full step per game while the side covers are drawn packed
        // tighter, so covers far out in the stacks are still on screen when their layout slot
        // is well past the edge. The row is laid out wide enough for every cover that shows
        // (the lazy stack only builds what's inside its frame), and drawn centred on screen.
        let reach = min(
            metrics.layoutDistance(forVisual: width / 2 + metrics.coverWidth / 2),
            metrics.step * 40
        ).rounded(.up)
        let rowWidth = reach * 2 + metrics.step
        // The scroll view's coordinate space starts at its content margin, so the middle
        // of the viewport is half a step in.
        let middle = metrics.step / 2
        return ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(Array(games.enumerated()), id: \.element.id) { index, game in
                    coverButton(game, index: index, metrics: metrics)
                        .frame(width: metrics.step, height: metrics.coverHeight)
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
        .contentMargins(.horizontal, reach, for: .scrollContent)
        .scrollTargetBehavior(CoverFlowSnapping(metrics: metrics, count: games.count, tracker: tracker))
        .scrollPosition($position, anchor: .center)
        .onScrollGeometryChange(for: Double.self) { geometry in
            geometry.contentOffset.x + geometry.contentInsets.leading
        } action: { _, offset in
            tracker.offset = offset
            let index = metrics.index(forOffset: offset, count: games.count)
            if liveIndex != index { liveIndex = index }
        }
        .onScrollPhaseChange { old, phase in
            if phase == .interacting, old != .interacting {
                tracker.start = tracker.offset
            }
            // Only a swipe coming to rest; the row also goes idle when the list changes,
            // before it's been moved to the right game.
            if phase == .idle, old == .interacting || old == .decelerating {
                settle(at: liveIndex)
            }
        }
        .frame(width: rowWidth, height: metrics.coverHeight)
        .frame(width: width)
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
                .frame(width: metrics.coverWidth, height: metrics.coverHeight)
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
                // Landscape has the width for one line: no second line held empty between
                // the name and the system.
                VStack(spacing: compactCaption ? 3 : 8) {
                    Text(game.displayName)
                        .font(RetroPlayFont.subheadline)
                        .foregroundStyle(RetroPlayTheme.primaryText(for: colorScheme))
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .lineLimit(compactCaption ? 1 : 2, reservesSpace: !compactCaption)
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

    private var compactCaption: Bool { verticalSizeClass == .compact }

    private func lastPlayedText(_ game: LibraryGame) -> String? {
        lastPlayed[game.id].map {
            "Played " + $0.formatted(.relative(presentation: .named, unitsStyle: .abbreviated))
        }
    }

    private func subtitle(_ game: LibraryGame) -> String {
        if missingGameIDs.contains(game.id) { return "File missing" }
        return lastPlayedText(game) ?? "Not played yet"
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


/// The row's live position, read by the snapping when a swipe is let go (a reference, so the
/// scroll behaviour sees the latest value without the view redrawing for it).
final class CoverFlowScrollTracker: @unchecked Sendable {
    /// Content offset from the first cover centred.
    var offset: Double = 0
    /// The offset when the current swipe began.
    var start: Double = 0
}

/// Snaps the row to a cover and keeps a flick from running away: one swipe moves about one
/// game, a hard flick a few (`CoverFlow.Metrics.restingIndex`).
@available(iOS 18.0, *)
struct CoverFlowSnapping: ScrollTargetBehavior {
    let metrics: CoverFlow.Metrics
    let count: Int
    let tracker: CoverFlowScrollTracker

    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        guard count > 0, metrics.step > 0 else { return }
        // The row is laid out a margin wide on each side of one step, so the target's left
        // edge is the offset from the first cover centred.
        let proposed = target.rect.minX
        // A scroll that isn't a swipe (sent to a cover) keeps its cover; a swipe is judged
        // from where the finger let go, not where the system would coast to.
        let velocity = Double(context.velocity.dx)
        let index = velocity == 0
            ? metrics.index(forOffset: proposed, count: count)
            : metrics.restingIndex(
                start: tracker.start,
                release: tracker.offset,
                velocity: velocity * Self.velocityScale,
                count: count
            )
        target.rect.origin.x = Double(index) * metrics.step
    }

    /// `TargetContext.velocity` comes in points per millisecond (UIScrollView's units).
    static let velocityScale: Double = 1000
}
