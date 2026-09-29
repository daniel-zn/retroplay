// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI
import RetroPlayCore

/// Hardware-inspired palettes. Layout accuracy first; tints are recognition cues, not skins.
@available(iOS 18.0, *)
enum PadPalette {
    enum GBA {
        static let chassis = Color(red: 0.36, green: 0.32, blue: 0.62)
        static let chassisStroke = Color(red: 0.55, green: 0.50, blue: 0.82)
        static let dpad = Color(red: 0.16, green: 0.14, blue: 0.22)
        static let dpadHeld = Color(red: 0.28, green: 0.24, blue: 0.40)
        static let face = Color(red: 0.42, green: 0.34, blue: 0.72)
        static let faceA = Color(red: 0.58, green: 0.42, blue: 0.88)
        static let ink = Color.white.opacity(0.92)
        static let startSelect = Color(red: 0.22, green: 0.18, blue: 0.34)
        static let shoulder = Color(red: 0.28, green: 0.24, blue: 0.46)
    }

    enum N64 {
        static let chassis = Color(red: 0.58, green: 0.58, blue: 0.60)
        static let chassisDark = Color(red: 0.42, green: 0.42, blue: 0.45)
        static let chassisStroke = Color.white.opacity(0.18)
        static let dpad = Color(red: 0.28, green: 0.28, blue: 0.30)
        static let stickWell = Color(red: 0.22, green: 0.22, blue: 0.24)
        static let stickNub = Color(red: 0.14, green: 0.14, blue: 0.16)
        static let a = Color(red: 0.18, green: 0.42, blue: 0.86)
        static let b = Color(red: 0.22, green: 0.70, blue: 0.36)
        static let c = Color(red: 0.96, green: 0.82, blue: 0.18)
        static let start = Color(red: 0.84, green: 0.18, blue: 0.20)
        static let z = Color(red: 0.16, green: 0.16, blue: 0.18)
        static let shoulder = Color(red: 0.48, green: 0.48, blue: 0.50)
        static let inkDark = Color(red: 0.12, green: 0.12, blue: 0.14)
        static let inkLight = Color.white.opacity(0.95)
    }

    enum NDS {
        static let chassis = Color(red: 0.30, green: 0.32, blue: 0.36)
        static let chassisStroke = Color(red: 0.62, green: 0.64, blue: 0.68)
        static let dpad = Color(red: 0.18, green: 0.18, blue: 0.20)
        static let a = Color(red: 0.82, green: 0.28, blue: 0.32)
        static let b = Color(red: 0.88, green: 0.72, blue: 0.22)
        static let x = Color(red: 0.32, green: 0.52, blue: 0.88)
        static let y = Color(red: 0.28, green: 0.68, blue: 0.42)
        static let shoulder = Color(red: 0.42, green: 0.44, blue: 0.48)
        static let touchBezel = Color(red: 0.52, green: 0.54, blue: 0.58)
        static let touchGlass = Color(red: 0.08, green: 0.09, blue: 0.11)
        static let ink = Color.white.opacity(0.94)
        static let inkDark = Color(red: 0.12, green: 0.12, blue: 0.14)
    }

    enum PSP {
        static let chassis = Color(red: 0.08, green: 0.08, blue: 0.09)
        static let chassisStroke = Color(red: 0.72, green: 0.74, blue: 0.78)
        static let dpad = Color(red: 0.18, green: 0.18, blue: 0.20)
        static let face = Color(red: 0.12, green: 0.12, blue: 0.13)
        static let triangle = Color(red: 0.28, green: 0.78, blue: 0.62)
        static let circle = Color(red: 0.90, green: 0.30, blue: 0.34)
        static let cross = Color(red: 0.38, green: 0.56, blue: 0.96)
        static let square = Color(red: 0.92, green: 0.48, blue: 0.72)
        static let silver = Color(red: 0.74, green: 0.76, blue: 0.80)
        static let nub = Color(red: 0.32, green: 0.32, blue: 0.34)
        static let ink = Color.white.opacity(0.92)
    }
}

// MARK: - Shapes

@available(iOS 18.0, *)
struct PlusShape: Shape {
    var armThickness: CGFloat

    func path(in rect: CGRect) -> Path {
        let t = min(armThickness, rect.width, rect.height)
        let x0 = rect.midX - t / 2
        let y0 = rect.midY - t / 2
        let radius = t * 0.22
        var path = Path()
        path.addRoundedRect(
            in: CGRect(x: x0, y: rect.minY, width: t, height: rect.height),
            cornerSize: CGSize(width: radius, height: radius)
        )
        path.addRoundedRect(
            in: CGRect(x: rect.minX, y: y0, width: rect.width, height: t),
            cornerSize: CGSize(width: radius, height: radius)
        )
        return path
    }
}

/// Regular octagon with flats on the cardinals (N64 Control Stick gate).
@available(iOS 18.0, *)
struct RegularOctagon: Shape {
    func path(in rect: CGRect) -> Path {
        let r = min(rect.width, rect.height) / 2
        let c = CGPoint(x: rect.midX, y: rect.midY)
        var path = Path()
        for i in 0..<8 {
            let angle = Double(i) * (.pi / 4) - .pi / 8
            let point = CGPoint(x: c.x + r * CGFloat(cos(angle)), y: c.y + r * CGFloat(sin(angle)))
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}

