// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// The library's Cover Flow view: where the covers stand, and which game is in the middle.
/// Kept free of SwiftUI so the geometry and the focus rules can be tested.
public enum CoverFlow {
    /// Sizes for one carousel, from the space it has.
    public struct Metrics: Equatable, Sendable {
        /// The slot each cover stands in, on its bottom edge: every cover is `coverWidth`
        /// wide, and as tall as its shape makes it (up to `coverHeight`, the tallest).
        public let coverWidth: Double
        public let coverHeight: Double
        /// Scroll distance from one cover to the next: the layout width of each item, and how
        /// far a finger drags to move one game. Wider than the drawn spacing of the stacks, so
        /// a swipe stays controlled however tightly the side covers stack.
        public let step: Double
        /// How far the first cover on the left stands from the middle one's centre: it tucks
        /// in under the middle cover's edge.
        public let firstGap: Double
        /// How far the first cover on the right stands from the middle one's centre. Every
        /// side cover faces right (its spine, on its left, turns towards the player), so on
        /// the right the edge nearer the middle comes forward and the stack lies on top; it
        /// stands far enough out that it never covers the middle cover, at the widest box.
        public let rightGap: Double
        /// How far apart the covers past the first stand in each side stack.
        public let stackSpacing: Double
        /// How deep the deepest box in the row is drawn (its side shows as a cover turns).
        public let boxDepth: Double
        /// How far the eye stands in front of each cover: the strength of the perspective.
        public let eye: Double

        public init(coverWidth: Double, coverHeight: Double, boxDepth: Double = 0) {
            self.coverWidth = coverWidth
            self.coverHeight = coverHeight
            self.boxDepth = boxDepth
            // At least 120 points, so small landscape covers don't make a swipe race.
            step = max((coverWidth * 0.42).rounded(), 120)
            firstGap = (coverWidth * 0.45).rounded()
            stackSpacing = (coverWidth * 0.17).rounded()
            eye = max(coverWidth, coverHeight) / CoverFlow.perspective
            // The first left cover's right edge (its side, turned towards the player) stops
            // just short of the middle cover's left edge, with a little air.
            let box = Box(width: coverWidth, height: coverHeight, depth: boxDepth)
            let middle = CoverFlow.span(box, yaw: 0, eye: eye)
            let side = CoverFlow.span(box, yaw: CoverFlow.sideAngle, eye: eye)
            rightGap = (middle.right - side.left + coverWidth * 0.01).rounded()
        }

        public init(coverSide: Double) {
            self.init(coverWidth: coverSide, coverHeight: coverSide)
        }

        /// Every cover is drawn this one width (scaled whole, never stretched; heights vary
        /// with each cover's shape), so the row reads evenly as it scrolls. The width is the
        /// largest that leaves room on the sides of `width` for the stacks and still fits the
        /// tallest cover shape in the list (`tallestAspect`, width over height) into `height`;
        /// never smaller than `minimum`. The slot is that tallest cover's height.
        public static func fitting(
            width: Double,
            height: Double,
            tallestAspect: Double = 0.71,
            deepestBox: Double = 0,
            minimum: Double = 110
        ) -> Metrics {
            let aspect = min(max(tallestAspect, 0.3), 2)
            let side = max(minimum, min(width * 0.6, height * aspect, 440).rounded(.down))
            return Metrics(
                coverWidth: side,
                coverHeight: (side / aspect).rounded(.up),
                boxDepth: (side * deepestBox).rounded()
            )
        }

        /// How big a cover of `aspect` (width over height) is drawn: the row's one width, as
        /// tall as its shape makes it. Only a shape taller than the slot allows (box art
        /// that runs taller than its system's usual box) is fitted to the height instead.
        public func coverSize(aspect: Double) -> (width: Double, height: Double) {
            guard aspect > 0 else { return (coverWidth, coverHeight) }
            let height = coverWidth / aspect
            if height <= coverHeight + 0.5 { return (coverWidth, height) }
            return (coverHeight * aspect, coverHeight)
        }

        /// Where a cover is drawn and how it turns, for an item `distance` points from the
        /// middle of the viewport (layout positions, negative to the left).
        ///
        /// Every side cover faces right, like a fanned deck, its spine towards the player:
        /// coming in from the right a cover turns up to face the player in the middle, then
        /// turns back the same way as it slides on into the left stack. It slides in step with the finger; the turn eases
        /// in and out.
        public func pose(distance: Double) -> Pose {
            let t = step > 0 ? distance / step : 0
            let near = min(abs(t), 1)
            let side: Double = t < 0 ? -1 : 1
            // Up to the first side cover they spread from the middle to its gap; past it they
            // stack `stackSpacing` apart.
            let gap = side > 0 ? rightGap : firstGap
            let drawn = near * gap + max(abs(t) - 1, 0) * stackSpacing
            let turn = near * near * (3 - 2 * near)
            return Pose(
                xShift: side * drawn - distance,
                // Facing right: the right edge recedes, the left (spine) edge comes forward. Covers
                // keep their size: only the turn and the perspective change how they look.
                rotation: turn * CoverFlow.sideAngle,
                dimming: min(abs(t) * 0.12, 0.45)
            )
        }

        /// How far from the middle (in layout points) an item sits when it's drawn `visual`
        /// points out: what the row has to lay out to fill the screen (on the left, the
        /// closer-packed side, so it covers both).
        public func layoutDistance(forVisual visual: Double) -> Double {
            guard firstGap > 0, stackSpacing > 0 else { return visual }
            let v = abs(visual)
            if v <= firstGap { return v / firstGap * step }
            return (1 + (v - firstGap) / stackSpacing) * step
        }

        /// The cover in the middle for a horizontal content offset (measured from the first
        /// cover centred), clamped to the list.
        public func index(forOffset offset: Double, count: Int) -> Int {
            guard count > 0, step > 0 else { return 0 }
            return min(max(Int((offset / step).rounded()), 0), count - 1)
        }

        /// Which cover a swipe comes to rest on, so a flick never runs away.
        ///
        /// - `start`: the content offset when the finger went down, `release` when it lifted
        ///   (both from the first cover centred).
        /// - `velocity`: points per second, positive towards later games.
        ///
        /// A slow release settles on the nearest cover. A swipe moves one game from the cover
        /// it started on (or as many as the finger dragged past). A fast flick carries on like
        /// momentum: past `flickVelocity`, one more cover for every `flickCoversPer` points per
        /// second, up to `maxSwipeTravel` covers in one gesture (unless the finger dragged
        /// further), so a hard flick runs through the library but never off to the end.
        public func restingIndex(start: Double, release: Double, velocity: Double, count: Int) -> Int {
            guard count > 0, step > 0 else { return 0 }
            let index: Int
            if abs(velocity) < CoverFlow.swipeVelocity {
                index = Int((release / step).rounded())
            } else {
                let direction = velocity > 0 ? 1 : -1
                let from = Int((start / step).rounded())
                let dragged = Int(((release - Double(from) * step) / step * Double(direction)).rounded())
                let speed = abs(velocity)
                let extra = speed > CoverFlow.flickVelocity
                    ? Int(((speed - CoverFlow.flickVelocity) / CoverFlow.flickCoversPer).rounded(.up))
                    : 0
                let travel = min(max(dragged, 1) + extra, max(CoverFlow.maxSwipeTravel, dragged))
                index = from + direction * travel
            }
            return min(max(index, 0), count - 1)
        }
    }

    /// Below this (points per second) a released swipe just settles on the nearest cover: a
    /// drag that stopped before letting go lands where the finger left it.
    public static let swipeVelocity: Double = 300
    /// Faster than this (points per second), a swipe is a flick and carries on; slower ones
    /// (a nudge) move one game.
    public static let flickVelocity: Double = 700
    /// Each this many points per second above `flickVelocity` carries a flick one cover further
    /// (a gentle 1100 pt/s flick about 3 covers, 2000 about 5, 5000 about 12, 8000 about 20).
    public static let flickCoversPer: Double = 380
    /// The most covers one swipe moves (unless the finger dragged further).
    public static let maxSwipeTravel = 24

    /// How a cover is drawn at one scroll position.
    public struct Pose: Equatable, Sendable {
        /// Points to move the cover away from its layout position (outward from the middle).
        public let xShift: Double
        /// Degrees about the vertical axis; 0 faces the player.
        public let rotation: Double
        /// 0…1 darkening for covers far from the middle.
        public let dimming: Double
    }

    /// How far the side covers turn away.
    public static let sideAngle: Double = 55

    /// How strongly the covers are drawn in perspective: the eye stands the cover's larger
    /// side over this in front of it.
    public static let perspective: Double = 0.3

    /// How deep each system's box is, for its width (a little shallower than the real thing,
    /// so the row stays compact): cardboard boxes for the cartridge systems, plastic cases for
    /// the disc and card ones.
    public static func boxDepth(_ system: SystemID) -> Double {
        switch system {
        case .atari7800: return 0.16
        case .nes: return 0.15
        case .snes, .gba: return 0.13
        case .n64, .genesis: return 0.11
        case .psp: return 0.08
        case .nds: return 0.07
        case .ps1: return 0.05
        }
    }

    /// Which cover is drawn over which: always the same order, so no two covers swap places
    /// mid-swipe. Later games lie on top. On the left each cover tucks under the one nearer
    /// the middle (covers leave from the top of the stack); on the right the stack lies over
    /// the cover nearer the middle (covers come in from the bottom).
    public static func layer(index: Int) -> Double {
        Double(index)
    }

    /// Which game to centre after the list changed.
    ///
    /// Within one filter (a new sort, an import, a delete) pass `currentIndex`, where the
    /// middle game stood: it stays in the middle while it's listed, and when it was removed
    /// the game that took its place is next.
    ///
    /// After switching filter pass `currentIndex: nil`: each filter returns to the game last
    /// centred there (`remembered`); a filter visited for the first time keeps the middle
    /// game when it has it (All → GBA on a GBA game).
    public static func focus(
        in ids: [UUID],
        current: UUID?,
        currentIndex: Int? = nil,
        remembered: UUID? = nil
    ) -> UUID? {
        guard !ids.isEmpty else { return nil }
        if let currentIndex {
            if let current, ids.contains(current) { return current }
            return ids[min(max(currentIndex, 0), ids.count - 1)]
        }
        if let remembered, ids.contains(remembered) { return remembered }
        if let current, ids.contains(current) { return current }
        return ids[0]
    }

    /// The game last centred in each filter, stored as one string in user defaults
    /// ("all=UUID;gba=UUID").
    public struct Memory: Equatable, Sendable {
        public private(set) var games: [String: UUID]

        public init(raw: String) {
            var games: [String: UUID] = [:]
            for entry in raw.split(separator: ";") {
                let parts = entry.split(separator: "=", maxSplits: 1)
                guard parts.count == 2, let id = UUID(uuidString: String(parts[1])) else { continue }
                games[String(parts[0])] = id
            }
            self.games = games
        }

        public var raw: String {
            games.keys.sorted().map { "\($0)=\(games[$0]!.uuidString)" }.joined(separator: ";")
        }

        public subscript(filter: String) -> UUID? {
            get { games[filter] }
            set { games[filter] = newValue }
        }
    }
}
