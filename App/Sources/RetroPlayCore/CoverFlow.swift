// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// The library's Cover Flow view: where the covers stand, and which game is in the middle.
/// Kept free of SwiftUI so the geometry and the focus rules can be tested.
public enum CoverFlow {
    /// Sizes for one carousel, from the space it has.
    public struct Metrics: Equatable, Sendable {
        /// The square slot each cover stands in (covers keep their own shape inside it).
        public let coverSide: Double
        /// Scroll distance from one cover to the next: the layout width of each item.
        /// Much less than a cover, so the side covers stack.
        public let step: Double
        /// How far the first cover on each side stands from the middle one's centre.
        public let firstGap: Double

        public init(coverSide: Double) {
            self.coverSide = coverSide
            step = (coverSide * 0.2).rounded()
            firstGap = (coverSide * 0.64).rounded()
        }

        /// The largest cover that fits `height` (above the caption) and leaves room on the
        /// sides of `width` for the stacks; never smaller than `minimum`.
        public static func fitting(width: Double, height: Double, minimum: Double = 110) -> Metrics {
            let side = min(height, width * 0.56, 420)
            return Metrics(coverSide: max(minimum, side.rounded(.down)))
        }

        /// Where a cover is drawn and how it turns, for an item `distance` points from the
        /// middle of the viewport (layout positions, negative to the left).
        public func pose(distance: Double) -> Pose {
            let t = step > 0 ? distance / step : 0
            let near = min(abs(t), 1)
            let side: Double = t < 0 ? -1 : 1
            // Up to the first gap the covers spread out from their layout spacing; past it
            // they keep the layout spacing, shifted out by the same amount.
            let shift = side * near * (firstGap - step)
            return Pose(
                xShift: shift,
                // Each side cover's outer edge turns away, so the ones behind it show.
                rotation: side * near * CoverFlow.sideAngle,
                scale: 1 - near * 0.22,
                dimming: min(abs(t) * 0.12, 0.45)
            )
        }

        /// The cover in the middle for a horizontal content offset (measured from the first
        /// cover centred), clamped to the list.
        public func index(forOffset offset: Double, count: Int) -> Int {
            guard count > 0, step > 0 else { return 0 }
            return min(max(Int((offset / step).rounded()), 0), count - 1)
        }
    }

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
