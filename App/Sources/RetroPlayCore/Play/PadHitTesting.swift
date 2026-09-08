import Foundation

/// Geometry helpers for on-screen pads. UI views map gestures through these so
/// D-pad / stick / DS touch behavior stays testable without SwiftUI.
public enum PadHitTesting {
    /// Four-way (+ optional diagonals) from a touch offset in view space (Y down).
    /// `diagonalRatio` is how much the weaker axis must match the stronger to count
    /// (0.38 ≈ generous diagonals, still ignores near-axis jitter).
    public static func dpad(
        dx: Double,
        dy: Double,
        deadzone: Double = 10,
        diagonalRatio: Double = 0.38
    ) -> (up: Bool, down: Bool, left: Bool, right: Bool) {
        let mag = (dx * dx + dy * dy).squareRoot()
        if mag < deadzone {
            return (false, false, false, false)
        }
        let ax = abs(dx)
        let ay = abs(dy)
        let up = dy < 0 && ay >= ax * diagonalRatio
        let down = dy > 0 && ay >= ax * diagonalRatio
        let left = dx < 0 && ax >= ay * diagonalRatio
        let right = dx > 0 && ax >= ay * diagonalRatio
        return (up, down, left, right)
    }

    /// Analog stick sample. View space (Y down) → stick space (Y up).
    /// Clamped to a unit circle, then scaled to `maxMagnitude` (N64 digital scaffold used ±80).
    public static func analog(
        dx: Double,
        dy: Double,
        radius: Double,
        maxMagnitude: Int8 = 80,
        deadzone: Double = 0.12
    ) -> (x: Int8, y: Int8) {
        guard radius > 0 else { return (0, 0) }
        var nx = dx / radius
        var ny = -dy / radius
        let mag = (nx * nx + ny * ny).squareRoot()
        if mag < deadzone {
            return (0, 0)
        }
        if mag > 1 {
            nx /= mag
            ny /= mag
        }
        let scale = Double(maxMagnitude)
        return (
            Int8(clamping: Int((nx * scale).rounded())),
            Int8(clamping: Int((ny * scale).rounded()))
        )
    }

    /// Map a point inside a view to NDS bottom-screen pixels (256×192).
    public static func ndsTouch(
        x: Double,
        y: Double,
        width: Double,
        height: Double
    ) -> (x: UInt16, y: UInt16) {
        guard width > 0, height > 0 else { return (0, 0) }
        let nx = min(1, max(0, x / width))
        let ny = min(1, max(0, y / height))
        return (UInt16((nx * 255).rounded(.down)), UInt16((ny * 191).rounded(.down)))
    }
}
