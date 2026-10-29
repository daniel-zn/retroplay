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

        /// Where the centre of a box `height` × `depth` stands for a cover `distance` points
        /// (in layout) from the middle, and how it's turned.
        public func place(distance: Double, height: Double, depth: Double)
            -> (x: Double, y: Double, yaw: Double, dimming: Double)
        {
            let pose = metrics.pose(distance: distance)
            return (distance + pose.xShift,
                    -metrics.coverHeight / 2 + height / 2 + lift(height: height, depth: depth),
                    pose.rotation,
                    pose.dimming)
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
