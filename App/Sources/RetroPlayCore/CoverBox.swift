// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Cover Flow's covers as boxes, for the row's spacing: how far a box reaches left, right,
/// up and down as it turns, seen from level with its top (`Stage` draws the scene itself).
///
/// Coordinates: x to the right, y down, z towards the player, from the box's centre. Turns are
/// in degrees about an axis.
extension CoverFlow {
    /// How far every box tips back (degrees about the horizontal axis; negative tips its top
    /// away), so the row is seen a little from above and the boxes' tops show.
    public static let pitch: Double = -12

    /// A cover's box: as wide and tall as its cover, `depth` deep, its front, side and top
    /// edges rounded to `radius` (0: sharp).
    public struct Box: Equatable, Sendable {
        public let width: Double
        public let height: Double
        public let depth: Double
        public let radius: Double

        public init(width: Double, height: Double, depth: Double, radius: Double = 0) {
            self.width = width
            self.height = height
            self.depth = depth
            // No more than half the depth, and a sliver of the width.
            self.radius = max(0, min(radius, depth / 2, width / 5, height / 5))
        }
    }

    typealias Vector = (x: Double, y: Double, z: Double)
    /// Rows of a 3 × 3 rotation for column vectors (`q = m · p`).
    typealias Matrix = [[Double]]

    /// A turn of `degrees` about `axis`.
    static func rotation(axis: Vector, degrees: Double) -> Matrix {
        let length = (axis.x * axis.x + axis.y * axis.y + axis.z * axis.z).squareRoot()
        guard length > 0 else { return [[1, 0, 0], [0, 1, 0], [0, 0, 1]] }
        let x = axis.x / length, y = axis.y / length, z = axis.z / length
        let a = degrees * .pi / 180, c = cos(a), s = sin(a), t = 1 - c
        return [
            [t * x * x + c, t * x * y - s * z, t * x * z + s * y],
            [t * x * y + s * z, t * y * y + c, t * y * z - s * x],
            [t * x * z - s * y, t * y * z + s * x, t * z * z + c],
        ]
    }

    static func multiply(_ a: Matrix, _ b: Matrix) -> Matrix {
        (0..<3).map { r in (0..<3).map { c in (0..<3).reduce(0) { $0 + a[r][$1] * b[$1][c] } } }
    }

    static func apply(_ m: Matrix, _ p: Vector) -> Vector {
        (m[0][0] * p.x + m[0][1] * p.y + m[0][2] * p.z,
         m[1][0] * p.x + m[1][1] * p.y + m[1][2] * p.z,
         m[2][0] * p.x + m[2][1] * p.y + m[2][2] * p.z)
    }

    /// How a box turned `yaw` degrees (positive faces right) stands: tipped back by `pitch`.
    static func boxTurn(yaw: Double) -> Matrix {
        multiply(rotation(axis: (1, 0, 0), degrees: pitch), rotation(axis: (0, 1, 0), degrees: yaw))
    }

    /// The eye stands level with the box's top edge (above its centre), so the row is seen
    /// looking a little down onto the boxes: y of the eye from the box's centre.
    static func eyeLevel(_ box: Box) -> Double { -box.height / 2 }

    /// Where a point (from the box's centre, turned) is drawn, from the box's centre. The
    /// drawing is lifted so a box facing the player sits square in its slot: looked at from
    /// level with its top, its front would otherwise be drawn lower than the flat cover.
    static func project(_ q: Vector, _ box: Box, eye: Double) -> (x: Double, y: Double) {
        let drawn = perspective(q, box, eye: eye)
        return (drawn.x, drawn.y + lift(box, eye: eye))
    }

    static func perspective(_ q: Vector, _ box: Box, eye: Double) -> (x: Double, y: Double) {
        let level = eyeLevel(box)
        let k = eye / (eye - q.z)
        return (q.x * k, level + (q.y - level) * k)
    }

    /// How far up a box is moved so its front, facing the player, is centred where the flat
    /// cover is.
    static func lift(_ box: Box, eye: Double) -> Double {
        let turn = boxTurn(yaw: 0)
        let top = perspective(apply(turn, (0, -box.height / 2, box.depth / 2)), box, eye: eye)
        let bottom = perspective(apply(turn, (0, box.height / 2, box.depth / 2)), box, eye: eye)
        return -(top.y + bottom.y) / 2
    }

    /// Where the box's eight corners are drawn, from its centre, turned `yaw`.
    static func corners(_ box: Box, yaw: Double, eye: Double) -> [(x: Double, y: Double)] {
        let turn = boxTurn(yaw: yaw)
        var drawn: [(x: Double, y: Double)] = []
        for x in [-box.width / 2, box.width / 2] {
            for y in [-box.height / 2, box.height / 2] {
                for z in [-box.depth / 2, box.depth / 2] {
                    drawn.append(project(apply(turn, (x, y, z)), box, eye: eye))
                }
            }
        }
        return drawn
    }

    /// How far left and right of its centre a box turned `yaw` is drawn.
    static func span(_ box: Box, yaw: Double, eye: Double) -> (left: Double, right: Double) {
        let xs = corners(box, yaw: yaw, eye: eye).map(\.x)
        return (xs.min() ?? 0, xs.max() ?? 0)
    }

}

extension CoverFlow.Metrics {

    /// How far left and right of its centre a box turned `yaw` is drawn.
    public func span(_ box: CoverFlow.Box, yaw: Double) -> (left: Double, right: Double) {
        CoverFlow.span(box, yaw: yaw, eye: eye)
    }

    /// How far a box's drawing is moved up so its front sits square in its slot (added after
    /// the turn, in the view's own coordinates).
    public func lift(_ box: CoverFlow.Box) -> Double {
        CoverFlow.lift(box, eye: eye)
    }

    /// Where a cover `offset` places from the middle is drawn when the row is at rest, left
    /// and right of its own place in the row: the area a tap on it should land in (a cover's
    /// layout slot is narrower than the cover and doesn't move with it). The right stack lies
    /// over the middle cover and all but touches it, its spine leaning in at the top where the
    /// middle cover's edge leans out at the bottom: a right cover's area stops at the middle
    /// cover's, so the whole middle cover plays it.
    public func restSpan(offset: Int) -> (left: Double, right: Double) {
        let stage = CoverFlow.Stage(metrics: self)
        func drawn(_ offset: Int) -> (left: Double, right: Double) {
            let distance = Double(offset) * step
            let xs = stage.drawnXs(distance: distance, width: coverWidth, height: coverHeight, depth: boxDepth)
            return ((xs.min() ?? 0) - distance, (xs.max() ?? 0) - distance)
        }
        let span = drawn(offset)
        guard offset > 0 else { return span }
        let distance = Double(offset) * step
        return (max(span.left, drawn(0).right - distance), span.right)
    }


    /// How far past the slot's top and bottom the tallest box reaches as it turns (tipped back
    /// and in perspective): room to leave above and below the row so covers clear the caption.
    public var overhang: Double {
        let box = CoverFlow.Box(width: coverWidth, height: coverHeight, depth: boxDepth)
        var reach = 0.0
        for yaw in stride(from: 0, through: CoverFlow.sideAngle, by: 1) {
            for corner in CoverFlow.corners(box, yaw: yaw, eye: eye) {
                reach = max(reach, abs(corner.y) - coverHeight / 2)
            }
        }
        return reach.rounded(.up)
    }
}
