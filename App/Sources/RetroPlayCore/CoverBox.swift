// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Cover Flow's covers as whole boxes: six faces turned together about the box's centre and
/// seen through one camera, so the faces meet and the row's spacing knows exactly where each
/// box reaches.
///
/// Coordinates: x to the right, y down, z towards the player, from the box's centre. Turns are
/// in degrees about an axis, the way SwiftUI's `rotation3DEffect` takes them.
extension CoverFlow {
    /// How far every box tips back (degrees about the horizontal axis; negative tips its top
    /// away), so the row is seen a little from above and the boxes' tops show.
    public static let pitch: Double = -12

    public enum Face: CaseIterable, Sendable {
        case front
        case back
        case left
        /// The side that turns towards the player (covers face left).
        case right
        case top
        case bottom
    }

    /// A cover's box: as wide and tall as its cover, `depth` deep.
    public struct Box: Equatable, Sendable {
        public let width: Double
        public let height: Double
        public let depth: Double

        public init(width: Double, height: Double, depth: Double) {
            self.width = width
            self.height = height
            self.depth = depth
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

    /// The same turn as an axis and an angle.
    static func axisAngle(_ m: Matrix) -> (axis: Vector, degrees: Double) {
        let cosine = min(max((m[0][0] + m[1][1] + m[2][2] - 1) / 2, -1), 1)
        let angle = acos(cosine)
        if angle < 1e-9 { return ((0, 1, 0), 0) }
        if .pi - angle < 1e-6 {
            // A half turn: the axis from the diagonal, signed by the largest component.
            var x = ((m[0][0] + 1) / 2).squareRoot(), y = ((m[1][1] + 1) / 2).squareRoot()
            var z = ((m[2][2] + 1) / 2).squareRoot()
            if x >= y, x >= z {
                y = m[0][1] >= 0 ? y : -y
                z = m[0][2] >= 0 ? z : -z
            } else if y >= z {
                x = m[0][1] >= 0 ? x : -x
                z = m[1][2] >= 0 ? z : -z
            } else {
                x = m[0][2] >= 0 ? x : -x
                y = m[1][2] >= 0 ? y : -y
            }
            return ((x, y, z), 180)
        }
        let s = 2 * sin(angle)
        return (((m[2][1] - m[1][2]) / s, (m[0][2] - m[2][0]) / s, (m[1][0] - m[0][1]) / s), angle * 180 / .pi)
    }

    /// How a box turned `yaw` degrees (negative faces left) stands: tipped back by `pitch`.
    static func boxTurn(yaw: Double) -> Matrix {
        multiply(rotation(axis: (1, 0, 0), degrees: pitch), rotation(axis: (0, 1, 0), degrees: yaw))
    }

    /// Where a face lies before the box turns: a turn taking the front's place to the face's,
    /// and how far out from the centre it stands.
    static func rest(_ face: Face, _ box: Box) -> (turn: Matrix, offset: Double) {
        switch face {
        case .front: return (rotation(axis: (0, 1, 0), degrees: 0), box.depth / 2)
        case .back: return (rotation(axis: (0, 1, 0), degrees: 180), box.depth / 2)
        case .right: return (rotation(axis: (0, 1, 0), degrees: 90), box.width / 2)
        case .left: return (rotation(axis: (0, 1, 0), degrees: -90), box.width / 2)
        case .top: return (rotation(axis: (1, 0, 0), degrees: 90), box.height / 2)
        case .bottom: return (rotation(axis: (1, 0, 0), degrees: -90), box.height / 2)
        }
    }

    /// A face's size as a flat picture: the front and back are the cover, the sides as deep
    /// as the box and as tall, the top and bottom as wide and as deep. Each is drawn with its
    /// top towards the box's top (the top and bottom: towards its back).
    public static func faceSize(_ face: Face, _ box: Box) -> (width: Double, height: Double) {
        switch face {
        case .front, .back: return (box.width, box.height)
        case .left, .right: return (box.depth, box.height)
        case .top, .bottom: return (box.width, box.depth)
        }
    }

    /// The eye stands level with the box's top edge (above its centre), so the row is seen
    /// looking a little down onto the boxes: y of the eye from the box's centre.
    static func eyeLevel(_ box: Box) -> Double { -box.height / 2 }

    /// Where a point (from the box's centre, turned) is drawn, from the box's centre.
    static func project(_ q: Vector, _ box: Box, eye: Double) -> (x: Double, y: Double) {
        let level = eyeLevel(box)
        let k = eye / (eye - q.z)
        return (q.x * k, level + (q.y - level) * k)
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

    static func transpose(_ m: Matrix) -> Matrix {
        (0..<3).map { r in (0..<3).map { c in m[c][r] } }
    }

    /// How far left and right of its centre a box turned `yaw` is drawn.
    static func span(_ box: Box, yaw: Double, eye: Double) -> (left: Double, right: Double) {
        let xs = corners(box, yaw: yaw, eye: eye).map(\.x)
        return (xs.min() ?? 0, xs.max() ?? 0)
    }

    /// Faces a box can show over the turns the row gives it (the rest always face away and
    /// aren't drawn).
    public static var shownFaces: [Face] {
        let box = Box(width: 1, height: 1.4, depth: 0.15)
        let metrics = Metrics(coverWidth: 1, coverHeight: 1.4, boxDepth: 0.15)
        return Face.allCases.filter { face in
            stride(from: -sideAngle, through: 0, by: 1).contains { metrics.isFacing(face, box, yaw: $0) }
        }
    }
}

extension CoverFlow.Metrics {
    /// How to draw one face with SwiftUI's `rotation3DEffect`, its view centred on the box:
    /// move it by `shift`, then turn it by `degrees` about `axis` round the point `anchorY`
    /// down its height (a unit point) and `anchorZ` behind it. That point is the same for
    /// every face (level with the box's top, at its centre's depth) and the eye looks out from
    /// it, so with `facePerspective` all the faces are drawn through one eye and meet.
    public func faceTurn(_ face: CoverFlow.Face, _ box: CoverFlow.Box, yaw: Double)
        -> (axis: (x: Double, y: Double, z: Double), degrees: Double,
            shift: (x: Double, y: Double), anchorY: Double, anchorZ: Double)
    {
        let rest = CoverFlow.rest(face, box)
        let turn = CoverFlow.multiply(CoverFlow.boxTurn(yaw: yaw), rest.turn)
        // The face's place before the turn, so turning round the eye's point lands it right:
        // its offset out from the centre, plus the pivot less the pivot turned back.
        let pivot: CoverFlow.Vector = (0, CoverFlow.eyeLevel(box), 0)
        let back = CoverFlow.apply(CoverFlow.transpose(turn), pivot)
        let shift = (x: pivot.x - back.x, y: pivot.y - back.y, z: rest.offset + pivot.z - back.z)
        let size = CoverFlow.faceSize(face, box)
        let axisAngle = CoverFlow.axisAngle(turn)
        return (axisAngle.axis, axisAngle.degrees, (shift.x, shift.y),
                size.height > 0 ? 0.5 + pivot.y / size.height : 0.5, -shift.z)
    }

    /// The `perspective` that puts the eye `eye` points from a face `width` × `height`
    /// (SwiftUI sets the eye at the view's larger side over `perspective`).
    public func facePerspective(width: Double, height: Double) -> Double {
        max(width, height) / eye
    }

    /// Where a face's point (`u`, `v` from its top left) is drawn, from the box's centre.
    public func drawn(_ face: CoverFlow.Face, _ box: CoverFlow.Box, yaw: Double, u: Double, v: Double) -> (x: Double, y: Double) {
        let rest = CoverFlow.rest(face, box)
        let size = CoverFlow.faceSize(face, box)
        let turn = CoverFlow.multiply(CoverFlow.boxTurn(yaw: yaw), rest.turn)
        let q = CoverFlow.apply(turn, (u - size.width / 2, v - size.height / 2, rest.offset))
        return CoverFlow.project(q, box, eye: eye)
    }

    /// Whether a face is turned towards the eye (otherwise it's hidden behind the box).
    public func isFacing(_ face: CoverFlow.Face, _ box: CoverFlow.Box, yaw: Double) -> Bool {
        let rest = CoverFlow.rest(face, box)
        let turn = CoverFlow.multiply(CoverFlow.boxTurn(yaw: yaw), rest.turn)
        let normal = CoverFlow.apply(turn, (0, 0, 1))
        let centre = CoverFlow.apply(turn, (0, 0, rest.offset))
        let level = CoverFlow.eyeLevel(box)
        return normal.z * (eye - centre.z) - normal.x * centre.x + normal.y * (level - centre.y) > 1e-9
    }

    /// How far left and right of its centre a box turned `yaw` is drawn.
    public func span(_ box: CoverFlow.Box, yaw: Double) -> (left: Double, right: Double) {
        CoverFlow.span(box, yaw: yaw, eye: eye)
    }

    /// How far past the slot's top and bottom the tallest box reaches as it turns (tipped back
    /// and in perspective): room to leave above and below the row so covers clear the caption.
    public var overhang: Double {
        let box = CoverFlow.Box(width: coverWidth, height: coverHeight, depth: boxDepth)
        var reach = 0.0
        for yaw in stride(from: -CoverFlow.sideAngle, through: 0, by: 1) {
            for corner in CoverFlow.corners(box, yaw: yaw, eye: eye) {
                reach = max(reach, abs(corner.y) - coverHeight / 2)
            }
        }
        return reach.rounded(.up)
    }
}
