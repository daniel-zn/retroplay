// SPDX-License-Identifier: GPL-3.0-or-later
import UIKit
import SwiftUI
import RetroPlayCore

/// The library as one row of covers you swipe through (the PS Vita RetroFlow launcher's
/// look): the middle cover faces you, the others stand turned away in a stack on each
/// side, on the same plain background as the grid.
struct LibraryCoverFlowView<Header: View>: View {
    let games: [LibraryGame]
    /// The system filter shown; each remembers its own middle game.
    let filter: SystemTab
    let onSelect: (LibraryGame) -> Void
    let artworkProvider: (LibraryGame) -> CoverArt?
    var onRequestDelete: ((LibraryGame) -> Void)?
    var lastPlayed: [UUID: Date] = [:]
    var missingGameIDs: Set<UUID> = []
    /// Takes controller moves (left / right, A).
    var controllerNavigation = false
    /// Bumped when a cover changes (box art downloaded, the player's pictures), so the 3D scene
    /// draws the covers again.
    var artRevision = 0
    @ViewBuilder let header: () -> Header

    @Environment(\.colorScheme) private var colorScheme
    @Environment(ControllerNavigator.self) private var navigator
    @AppStorage("retroplay.coverFlowFocus") private var memoryRaw = ""
    @State private var position = ScrollPosition(idType: UUID.self)
    /// The cover in the middle right now (moves while swiping).
    @State private var liveIndex = 0
    /// The game the carousel came to rest on (or was sent to): what's remembered, and what
    /// stays in the middle when the list changes.
    @State private var settledID: UUID?
    @State private var listKey: ListKey?
    @State private var captionHeight: CGFloat = 0
    /// Where the row is right now, for the snapping to know where a swipe was let go.
    @State private var tracker = CoverFlowScrollTracker()
    @State private var scene = CoverFlowScene()
    @State private var page: Page?
    @State private var pageHold = CoverFlowPageHold()
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private struct ListKey: Equatable {
        let filter: SystemTab
        let ids: [UUID]
    }

    private var focusedGame: LibraryGame? {
        games.isEmpty ? nil : games[min(liveIndex, games.count - 1)]
    }

    /// The tallest cover shape among the games in the row, so every cover can share one width.
    /// From each system's box shape, with a little room for box art that runs taller.
    private var tallestAspect: Double {
        let shapes = games.map { Double(RetroPlayTheme.boxArtAspect($0.systemID)) }
        return (shapes.min() ?? 0.71) * 0.97
    }

    var body: some View {
        #if DEBUG
        let _ = LibraryWorkProbe.coverFlow += 1
        #endif
        // The page is laid out for the size it's held at (`page`), not followed frame by frame:
        // as the bar above grows and shrinks (the search field showing or hiding, the title
        // collapsing) the page just slides, and nothing in it is laid out again.
        Color.clear
            .onGeometryChange(for: Page.self) { proxy in
                Page(width: proxy.size.width, height: proxy.size.height,
                     top: proxy.safeAreaInsets.top, bottom: proxy.safeAreaInsets.bottom)
            } action: { pageChanged(to: $0) }
            .overlay {
                if let page {
                    content(page)
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
    }

    /// The size and safe area the page is laid out for.
    private struct Page: Equatable {
        var width: CGFloat
        var height: CGFloat
        var top: CGFloat
        var bottom: CGFloat
    }

    /// Takes a new page size, except one where only the bar above moved after the page was
    /// pulled: that's the search field or the large title coming and going, which slides the
    /// page without changing what fits on it. Before any pull it's the title settling as its
    /// subtitle comes in, taken once it holds.
    private func pageChanged(to new: Page) {
        guard let old = page,
              // The bar's move nudges the other edges by a point or so as it rounds.
              abs(new.width - old.width) < 0.5, abs(new.bottom - old.bottom) < 3,
              abs((new.height + new.top + new.bottom) - (old.height + old.top + old.bottom)) < 3
        else {
            page = new
            pageHold.reset()
            return
        }
        if new != old { pageHold.settle { page = new } }
    }

    @ViewBuilder
    private func content(_ page: Page) -> some View {
        #if DEBUG
        let _ = LibraryWorkProbe.pagePasses += 1
        #endif
        // Landscape is short: the row runs down through the home-indicator strip, the caption
        // sits at the bottom instead of being centred, and the covers take the height saved.
        let landscape = page.width > page.height
        let bottomRoom = landscape ? page.bottom : 0
        let room = page.height + bottomRoom - captionHeight - (landscape ? 24 : 32)
        let deepest = games.map { CoverFlow.boxDepth($0.systemID) }.max() ?? 0
        // Turned covers' near edges reach past the slot: size the row with that room taken
        // off, and leave it below the covers so they clear the caption.
        let overhang = CGFloat(CoverFlow.Metrics.fitting(
            width: page.width, height: room, tallestAspect: tallestAspect, deepestBox: deepest
        ).overhang)
        // Landscape grows the covers upwards: the room above takes no overhang allowance.
        let metrics = CoverFlow.Metrics.fitting(
            width: page.width,
            height: room - overhang * (landscape ? 1 : 2),
            tallestAspect: tallestAspect,
            deepestBox: deepest
        )
        ScrollView(.vertical) {
            // At least the height it's laid out for (the search field showing pushes it down),
            // all of the screen when there's more (the title collapsed to the bar), more when
            // the text needs it: by layout alone, so none of these runs this view again.
            CoverFlowPageFill {
                Color.clear.containerRelativeFrame(.vertical)
                VStack(spacing: 0) {
                    header()
                    if !games.isEmpty {
                        Spacer(minLength: 0)
                        CoverFlowRow(
                            games: games,
                            filter: filter,
                            metrics: metrics,
                            width: page.width,
                            missingGameIDs: missingGameIDs,
                            lastPlayed: lastPlayed,
                            artRevision: artRevision,
                            liveIndex: $liveIndex,
                            position: $position,
                            tracker: tracker,
                            scene: scene,
                            onSelect: onSelect,
                            artworkProvider: artworkProvider,
                            onRequestDelete: onRequestDelete,
                            move: { move(to: $0, animated: $1) },
                            settle: { settle(at: $0) }
                        )
                        .equatable()
                            .padding(.top, landscape ? 4 : 8 + overhang)
                            .padding(.bottom, (landscape ? 6 : 12) + overhang)
                        // The covers are laid out around the caption's room (the caption as it
                        // was before it grew, the same for every game), so they neither move nor
                        // shrink; the caption shown is drawn over that room. Portrait: centred in
                        // all the room below the covers (the room and the free space under it).
                        VStack(spacing: 0) {
                            captionRoom
                                .padding(.horizontal, 24)
                                .padding(.bottom, landscape ? 14 : 16)
                                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { captionHeight = $0 }
                            if !landscape {
                                Spacer(minLength: 0)
                            }
                        }
                        .overlay {
                            caption
                                .padding(.horizontal, 24)
                                .offset(y: landscape ? -4 : 0)
                        }
                        .zIndex(1)
                    }
                }
                .frame(minHeight: page.height + bottomRoom)
            }
        }
        .ignoresSafeArea(edges: landscape ? .bottom : [])
        // The page scrolls only when large text leaves no room (landscape), but it always
        // pulls down, as the grid does, to show the search field under the title. The covers
        // swipe only sideways, so a pull down that starts on them moves the page.
        .scrollBounceBehavior(.always, axes: .vertical)
        .onScrollPhaseChange { _, phase in pageHold.phase(phase) }
    }

    // MARK: Caption

    /// Title, system and last played for the middle game: a headline-sized title (two lines in
    /// portrait, then "…"; one in landscape) over a readable system / last-played line.
    private var caption: some View {
        ZStack {
            if let game = focusedGame {
                VStack(spacing: compactCaption ? 4 : 10) {
                    Text(game.displayName)
                        .font(RetroPlayFont.titleFace(compactCaption ? .headline : .title3))
                        .foregroundStyle(RetroPlayTheme.primaryText(for: colorScheme))
                        .multilineTextAlignment(.center)
                        .lineSpacing(0)
                        // Only the lines a title needs, so a short title sits with its system line.
                        .lineLimit(compactCaption ? 1 : 2)
                        .truncationMode(.tail)
                        // Glitches soon after the covers settle on it, then now and then.
                        .retroPlayTitleGlitch(game.displayName)
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
                    .font(RetroPlayFont.subheadline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                }
                .id(game.id)
                .transition(.opacity)
            }
        }
        .frame(maxWidth: 560)
        .animation(.easeOut(duration: 0.18), value: focusedGame?.id)
        // VoiceOver reads the same on each cover. Debug builds keep the caption for UI tests
        // that ask (`-RetroPlayTestCaptionAccessible YES`), so they can check where it is.
        .accessibilityHidden(!Self.captionAccessibleForTests)
        .accessibilityIdentifier("coverFlow.caption")
    }

    /// The room the covers leave for the caption, unseen: the caption as it was before it grew,
    /// two title lines in portrait (one in landscape) over the detail line, whatever the game.
    private var captionRoom: some View {
        VStack(spacing: compactCaption ? 3 : 8) {
            Text(verbatim: " ")
                .font(RetroPlayFont.titleFace(.subheadline))
                .lineSpacing(0)
                .lineLimit(compactCaption ? 1 : 2, reservesSpace: !compactCaption)
            Text(verbatim: " ")
                .font(RetroPlayFont.footnote)
        }
        .frame(maxWidth: 560)
        .hidden()
    }

    private static var captionAccessibleForTests: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "RetroPlayTestCaptionAccessible")
        #else
        false
        #endif
    }

    private var compactCaption: Bool { verticalSizeClass == .compact }


    private func subtitle(_ game: LibraryGame) -> String {
        if missingGameIDs.contains(game.id) { return "File missing" }
        return coverFlowLastPlayedText(lastPlayed[game.id]) ?? "Not played yet"
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

}

/// "Played 2 days ago", for the caption and VoiceOver.
private func coverFlowLastPlayedText(_ date: Date?) -> String? {
    date.map { "Played " + $0.formatted(.relative(presentation: .named, unitsStyle: .abbreviated)) }
}

/// The row of covers: invisible buttons in a sideways scroll, with the 3D scene drawing the boxes
/// behind them. A view of its own, compared by what it shows (`.equatable()`), so the page around
/// it changing size (the bar growing as a pull down brings in the search field) doesn't build the
/// row again.
private struct CoverFlowRow: View, Equatable {
    let games: [LibraryGame]
    /// What `move` and `settle` remember the middle game for.
    let filter: SystemTab
    let metrics: CoverFlow.Metrics
    let width: CGFloat
    let missingGameIDs: Set<UUID>
    let lastPlayed: [UUID: Date]
    /// How many covers have box art, so the scene draws them again when art comes in.
    let artRevision: Int
    @Binding var liveIndex: Int
    @Binding var position: ScrollPosition
    let tracker: CoverFlowScrollTracker
    let scene: CoverFlowScene
    let onSelect: (LibraryGame) -> Void
    let artworkProvider: (LibraryGame) -> CoverArt?
    let onRequestDelete: ((LibraryGame) -> Void)?
    /// Brings a game to the middle (animated or not) and remembers it.
    let move: (Int, Bool) -> Void
    /// Remembers the game a swipe came to rest on.
    let settle: (Int) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled

    /// The actions are left out: they read only what's compared here (and state).
    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.games == rhs.games && lhs.filter == rhs.filter && lhs.metrics == rhs.metrics
            && lhs.width == rhs.width && lhs.missingGameIDs == rhs.missingGameIDs
            && lhs.lastPlayed == rhs.lastPlayed && lhs.artRevision == rhs.artRevision
    }

    var body: some View {
        #if DEBUG
        LibraryWorkProbe.carousel += 1
        #endif
        // A swipe moves the row a full step per game while the side covers are drawn packed
        // tighter, so covers far out in the stacks are still on screen when their layout slot
        // is well past the edge. The row is laid out wide enough for every cover that shows
        // (the lazy stack only builds what's inside its frame), and drawn centred on screen.
        let reach = min(
            metrics.layoutDistance(forVisual: width / 2 + metrics.coverWidth / 2),
            metrics.step * 40
        ).rounded(.up)
        let rowWidth = reach * 2 + metrics.step
        // The boxes are drawn by the 3D scene behind the (invisible) row of buttons. Its view
        // is centred on the eye, level with the slot's top, and tall enough to reach past the
        // slot's floor by the boxes' overhang.
        let stageHeight = (metrics.coverHeight + metrics.overhang + 24) * 2
        let input = CoverFlowScene.Input(
            games: games,
            stage: CoverFlow.Stage(metrics: metrics),
            size: CGSize(width: width, height: stageHeight),
            missing: missingGameIDs,
            liveIndex: liveIndex,
            dark: colorScheme == .dark,
            artRevision: artRevision
        )
        return ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(Array(games.enumerated()), id: \.element.id) { index, game in
                    coverButton(game, index: index, metrics: metrics)
                        .frame(width: metrics.step, height: metrics.coverHeight)
                        // One fixed order (earlier games on top), so covers never swap
                        // places mid-swipe.
                        .zIndex(CoverFlow.layer(index: index))
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
                settle(liveIndex)
            }
        }
        .frame(width: rowWidth, height: metrics.coverHeight)
        .frame(width: width)
        .background(alignment: .top) {
            CoverFlowStageView(scene: scene, height: stageHeight)
                .frame(width: width)
                .offset(y: -stageHeight / 2)
        }
        .onChange(of: input, initial: true) { _, input in
            scene.offset = { [tracker] in tracker.offset }
            scene.artwork = artworkProvider
            scene.input = input
        }
        .sensoryFeedback(.selection, trigger: liveIndex)
    }

    private func coverButton(
        _ game: LibraryGame,
        index: Int,
        metrics: CoverFlow.Metrics
    ) -> some View {
        let missing = missingGameIDs.contains(game.id)
        return Button {
            if index == liveIndex || voiceOverEnabled {
                onSelect(game)
            } else {
                move(index, true)
            }
        } label: {
            // The box is drawn by the 3D scene behind; this is just where a tap on it lands.
            Color.clear
                .contentShape(TapArea(span: metrics.restSpan(offset: index - liveIndex)))
                .frame(width: metrics.coverWidth, height: metrics.coverHeight)
        }
        .buttonStyle(RetroPlayPressStyle())
        .accessibilityLabel(
            missing
                ? "\(game.displayName), \(game.systemID.displayName), file missing"
                : "\(game.displayName), \(game.systemID.displayName)"
        )
        .accessibilityValue(coverFlowLastPlayedText(lastPlayed[game.id]) ?? "")
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
            // The cover facing front, whichever way it's turned in the row, at its size in the
            // row: the preview is exactly the cover, nothing around it.
            let cover = artworkProvider(game)
            let size = metrics.coverSize(aspect: Double(CoverArt.aspect(cover, game: game)))
            CoverFlowCover(game: game, cover: cover, missing: missing)
                .frame(width: size.width, height: size.height)
                .accessibilityElement()
                .accessibilityIdentifier("library.coverPreview")
        }
    }
}

/// One cover facing front, filling its frame (the long-press preview).
private struct CoverFlowCover: View {
    let game: LibraryGame
    let cover: CoverArt?
    let missing: Bool

    var body: some View {
        GameArtworkView(
            game: game,
            artwork: cover?.image,
            isBoxArt: cover?.isBoxArt ?? false,
            cornerRadius: 10,
            labelTitleSize: 16
        )
        .opacity(missing ? 0.45 : 1)
        .overlay(alignment: .topTrailing) {
            if missing {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white, .orange)
                    .padding(8)
            }
        }
    }
}

/// A cover's tap area: where it's drawn at rest, left and right of its place in the row (from its
/// centre), full height. Taps land there, so a tap on the middle cover can't fall to a neighbour
/// stacked over its slot.
private struct TapArea: Shape {
    let span: (left: Double, right: Double)

    func path(in rect: CGRect) -> Path {
        Path(CGRect(x: rect.midX + span.left, y: rect.minY,
                           width: max(span.right - span.left, 1), height: rect.height))
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

/// Lays the page out (the second view) at least as tall as the first (the screen's height),
/// or taller if the page needs it.
struct CoverFlowPageFill: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard subviews.count == 2 else { return .zero }
        let width = proposal.width
        let screen = subviews[0].sizeThatFits(ProposedViewSize(width: width, height: nil)).height
        let page = subviews[1].sizeThatFits(ProposedViewSize(width: width, height: nil))
        return CGSize(width: width ?? page.width, height: max(screen, page.height))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 2 else { return }
        let size = ProposedViewSize(width: bounds.width, height: bounds.height)
        subviews[0].place(at: bounds.origin, proposal: size)
        subviews[1].place(at: bounds.origin, proposal: size)
    }
}

/// Whether the page has been pulled since it took its size (a reference, so the scrolling
/// doesn't run the view again). Once it has, the bar's height is the pull's doing (the search
/// field showing, the title collapsed), not a new size for the page.
@MainActor
final class CoverFlowPageHold {
    private(set) var pulled = false
    /// A bar height waiting to be taken, if no pull starts first.
    private var waiting: Task<Void, Never>?

    func phase(_ phase: ScrollPhase) {
        guard phase.isScrolling else { return }
        pulled = true
        waiting?.cancel()
    }

    /// The page took a new size (the window changed): the bar's height counts again until
    /// the next pull.
    func reset() {
        pulled = false
        waiting?.cancel()
    }

    /// Takes a bar height that holds for a moment with no pull: the title settling as its
    /// subtitle comes in. A pull's first frame comes before its scroll phase does; the pull
    /// cancels it.
    func settle(_ take: @escaping @MainActor () -> Void) {
        guard !pulled else { return }
        waiting?.cancel()
        waiting = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, let self, !self.pulled else { return }
            take()
        }
    }
}

/// Snaps the row to a cover and keeps a flick from running away: one swipe moves about one
/// game, a hard flick a few (`CoverFlow.Metrics.restingIndex`).
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
