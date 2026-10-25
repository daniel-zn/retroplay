// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// The library's Cover Flow view: where the covers stand, and which game is in the middle.
/// Kept free of SwiftUI so the geometry and the focus rules can be tested.
public enum CoverFlow {
    /// Sizes for one carousel, from the space it has.
    public struct Metrics: Equatable, Sendable {
        /// The slot each cover stands in, on its bottom edge (covers keep their own shape
        /// inside it). Square in landscape; taller in portrait, for upright boxes.
        public let coverWidth: Double
        public let coverHeight: Double
        /// Scroll distance from one cover to the next: the layout width of each item, and how
        /// far a finger drags to move one game. Wider than the drawn spacing of the stacks, so
        /// a swipe stays controlled however tightly the side covers stack.
        public let step: Double
        /// How far the first cover on each side stands from the middle one's centre.
        public let firstGap: Double
        /// How far apart the covers past the first stand in each side stack.
        public let stackSpacing: Double

        public init(coverWidth: Double, coverHeight: Double) {
            self.coverWidth = coverWidth
            self.coverHeight = coverHeight
            // At least 120 points, so small landscape covers don't make a swipe race.
            step = max((coverWidth * 0.42).rounded(), 120)
            firstGap = (coverWidth * 0.5).rounded()
            stackSpacing = (coverWidth * 0.13).rounded()
        }

        public init(coverSide: Double) {
            self.init(coverWidth: coverSide, coverHeight: coverSide)
        }

        /// The largest cover that fits `height` (above the caption) and leaves room on the
        /// sides of `width` for the stacks; never smaller than `minimum`. In portrait the
        /// width limits it and the slot grows taller, so upright boxes fill the screen.
        public static func fitting(width: Double, height: Double, minimum: Double = 110) -> Metrics {
            let side = max(minimum, min(width * 0.8, height, 440).rounded(.down))
            let tall = max(side, min(height, side * 1.35).rounded(.down))
            return Metrics(coverWidth: side, coverHeight: tall)
        }

        /// Where a cover is drawn and how it turns, for an item `distance` points from the
        /// middle of the viewport (layout positions, negative to the left).
        public func pose(distance: Double) -> Pose {
            let t = step > 0 ? distance / step : 0
            // Between the middle and the first side spot a cover eases: it lingers in the
            // middle (and at the side), then crosses quickly. Eased the same both ways, so two
            // passing covers stay `firstGap` apart in all.
            let near = CoverFlow.linger(min(abs(t), 1))
            let side: Double = t < 0 ? -1 : 1
            // Up to the first side cover they spread from the middle to `firstGap`; past it
            // they stack `stackSpacing` apart.
            let drawn = near * firstGap + max(abs(t) - 1, 0) * stackSpacing
            // The turn and the shrink lead the slide: a cover leaving the middle turns fast at
            // first, one arriving stays turned until it's nearly there. So when the two pass
            // (and swap which is in front) both are turned edge-on enough not to overlap,
            // even at the widest cover shape.
            let turn = 1 - pow(1 - near, CoverFlow.turnCurve)
            return Pose(
                xShift: side * drawn - distance,
                // Side covers turn to face the middle, as in Cover Flow and RetroFlow: the
                // inner edge recedes and the outer edge comes forward.
                rotation: -side * turn * CoverFlow.sideAngle,
                scale: 1 - turn * CoverFlow.sideShrink,
                dimming: min(abs(t) * 0.12, 0.45)
            )
        }

        /// How far from the middle (in layout points) an item sits when it's drawn `visual`
        /// points out: what the row has to lay out to fill the screen.
        public func layoutDistance(forVisual visual: Double) -> Double {
            guard firstGap > 0, stackSpacing > 0 else { return visual }
            let v = abs(visual)
            if v <= firstGap { return CoverFlow.unlinger(v / firstGap) * step }
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
        public let scale: Double
        /// 0…1 darkening for covers far from the middle.
        public let dimming: Double
    }

    /// How far the side covers turn away.
    public static let sideAngle: Double = 58

    /// How strongly the middle cover lingers before it slides away (0 = it moves in step
    /// with the finger, 1 = it starts still and catches up in the middle of the move).
    public static let lingering: Double = 1

    /// Eases `u` (0 in the middle, 1 at the first side spot) along a smoothstep, mixed in by
    /// `lingering`. Symmetric: `linger(u) + linger(1 - u) == 1`.
    static func linger(_ u: Double) -> Double {
        let smooth = u * u * (3 - 2 * u)
        return u + (smooth - u) * lingering
    }

    /// The `u` that `linger` maps to `eased` (bisection: it only runs while laying out).
    static func unlinger(_ eased: Double) -> Double {
        if eased <= 0 { return 0 }
        if eased >= 1 { return 1 }
        var low = 0.0, high = 1.0
        for _ in 0..<40 {
            let mid = (low + high) / 2
            if linger(mid) < eased { low = mid } else { high = mid }
        }
        return (low + high) / 2
    }
    /// How much smaller the side covers are drawn (0.22 = 78% of the middle one).
    public static let sideShrink: Double = 0.22
    /// How strongly the turn leads the slide (1 = in step with it). At 4 a cover halfway
    /// between the middle and the first side spot is turned 54°, so two passing covers clear
    /// each other.
    public static let turnCurve: Double = 4

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
