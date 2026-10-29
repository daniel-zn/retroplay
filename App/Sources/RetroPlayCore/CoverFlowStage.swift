// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

extension CoverFlow {
    /// The row as a 3D scene seen through one camera: where each box stands and turns, what
    /// the camera sees, and which covers are worth drawing. Points throughout; x to the
    /// right, y up, z towards the player, from the middle of the covers' slot.
    public struct Stage: Equatable, Sendable {
        public let metrics: Metrics

        public init(metrics: Metrics) {
            self.metrics = metrics
        }

        /// The eye is level with the top of the slot (so the boxes' tops show as they tip
        /// back), `metrics.eye` in front of the row.
        public var eyeHeight: Double { metrics.coverHeight / 2 }

        /// How far in front of the row the eye stands.
        public var eyeDistance: Double { metrics.eye }

        /// The camera's vertical field of view (degrees) for a view `height` points tall,
        /// centred on the eye: the slot's plane is drawn at its own size.
        public func fieldOfView(height: Double) -> Double {
            2 * atan(height / 2 / eyeDistance) * 180 / .pi
        }

        /// How a box at rest is turned: tipped back by `pitch`, turned `yaw` (positive faces
        /// right). Rows for column vectors, in this scene's axes (y up).
        static func turn(yaw: Double) -> Matrix {
            multiply(rotation(axis: (1, 0, 0), degrees: pitch), rotation(axis: (0, 1, 0), degrees: yaw))
        }

        /// Where a point of the scene is drawn, from the slot's middle (y up).
        public func drawn(_ point: (x: Double, y: Double, z: Double)) -> (x: Double, y: Double) {
            let k = eyeDistance / (eyeDistance - point.z)
            return (point.x * k, eyeHeight + (point.y - eyeHeight) * k)
        }

        /// How far a box `height` × `depth` is raised (or lowered) so that, facing the player
        /// in the middle, its front is drawn just where the flat cover stood on the slot's
        /// floor (seen from above and tipped back, it would otherwise sit low).
        public func lift(height: Double, depth: Double) -> Double {
            let flat = -metrics.coverHeight / 2 + height / 2
            let turn = Self.turn(yaw: 0)
            let top = CoverFlow.apply(turn, (0, height / 2, depth / 2))
            let bottom = CoverFlow.apply(turn, (0, -height / 2, depth / 2))
            func middle(_ raise: Double) -> Double {
                let a = drawn((top.x, flat + raise + top.y, top.z)).y
                let b = drawn((bottom.x, flat + raise + bottom.y, bottom.z)).y
                return (a + b) / 2
            }
            // The drawn middle moves in step with the raise (scaled by the perspective).
            let atZero = middle(0), atOne = middle(1)
            guard atOne != atZero else { return 0 }
            return (flat - atZero) / (atOne - atZero)
        }

        /// How far the middle cover stands forward, towards the eye (points): clear of the
        /// side covers' near edges, which turn towards the player beside it.
        public var forward: Double { metrics.coverWidth * 0.3 }

        /// Where the centre of a box `height` × `depth` stands for a cover `distance` points
        /// (in layout) from the middle, how it's turned, and how much it's scaled.
        ///
        /// A cover facing the player comes `forward` towards the eye and is scaled down to
        /// match, so it's drawn exactly where and as large as it would stand in the row, but in
        /// front of its neighbours rather than through them. Turning away it goes back.
        public func place(distance: Double, height: Double, depth: Double)
            -> (x: Double, y: Double, z: Double, scale: Double, yaw: Double, dimming: Double)
        {
            let pose = metrics.pose(distance: distance)
            let x = distance + pose.xShift
            let y = -metrics.coverHeight / 2 + height / 2 + lift(height: height, depth: depth)
            let facing = 1 - min(abs(pose.rotation) / CoverFlow.sideAngle, 1)
            // Slid along the line to the eye: drawn the same, standing nearer.
            let scale = (eyeDistance - forward * facing) / eyeDistance
            return (x * scale,
                    eyeHeight + (y - eyeHeight) * scale,
                    eyeDistance * (1 - scale),
                    scale,
                    pose.rotation,
                    pose.dimming)
        }

        /// Where a box `width` × `height` × `depth`'s corners are drawn across the view (x, from
        /// the slot's middle) for a cover `distance` points from the middle.
        public func drawnXs(distance: Double, width: Double, height: Double, depth: Double) -> [Double] {
            let place = place(distance: distance, height: height, depth: depth)
            let turn = Self.turn(yaw: place.yaw)
            var xs: [Double] = []
            for x in [-width / 2, width / 2] {
                for y in [-height / 2, height / 2] {
                    for z in [-depth / 2, depth / 2] {
                        let q = CoverFlow.apply(turn, (x * place.scale, y * place.scale, z * place.scale))
                        xs.append(drawn((place.x + q.x, place.y + q.y, place.z + q.z)).x)
                    }
                }
            }
            return xs
        }

        /// The covers worth drawing at scroll `offset` (from the first cover centred) in a view
        /// `width` points wide: every one whose box can reach into it.
        public func window(offset: Double, count: Int, width: Double) -> Range<Int> {
            guard count > 0, metrics.step > 0 else { return 0..<0 }
            let reach = metrics.layoutDistance(forVisual: width / 2 + metrics.coverWidth) + metrics.step
            let first = max(0, Int(((offset - reach) / metrics.step).rounded(.down)))
            let last = min(count - 1, Int(((offset + reach) / metrics.step).rounded(.up)))
            return first <= last ? first..<(last + 1) : 0..<0
        }
    }
}
