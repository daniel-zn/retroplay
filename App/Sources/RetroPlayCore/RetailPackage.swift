// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// The parts every game's retail package shares on a system (North American releases): what
/// it's made of, the band its front carries, and how its spine is laid out. The library draws
/// boxes from this: a game's own art and title fill it in, and a game without box art still
/// gets its system's package. Names only, no logos: plain text such as "PSP".
public struct RetailPackage: Equatable, Sendable {
    public enum Material: Equatable, Sendable {
        case cardboard
        /// A keep case (PSP, DS) or a clamshell (Genesis).
        case plasticCase
        /// A CD jewel case.
        case jewelCase
    }

    public enum Edge: Equatable, Sendable {
        case top
        case bottom
        case leading
    }

    public enum Pattern: Equatable, Sendable {
        case plain
        /// Fine horizontal lines (the NES "black box" grid, the Genesis top band).
        case gridLines
        /// Four coloured bars (the N64 band).
        case colorBars
        /// A thin coloured rule along the band's inner edge.
        case rule(RGB)
    }

    public struct RGB: Equatable, Sendable {
        public let red: Double
        public let green: Double
        public let blue: Double

        public init(_ red: Double, _ green: Double, _ blue: Double) {
            self.red = red
            self.green = green
            self.blue = blue
        }

        public init(white: Double) {
            self.init(white, white, white)
        }

        /// Relative luminance (sRGB weights), for picking text that reads on it.
        public var luminance: Double { 0.2126 * red + 0.7152 * green + 0.0722 * blue }
        public var isDark: Bool { luminance < 0.5 }
    }

    /// A band across one edge of a face.
    public struct Band: Equatable, Sendable {
        public let edge: Edge
        /// Thickness as a share of the face: of its height for top and bottom bands, of its
        /// width for a leading band.
        public let thickness: Double
        public let color: RGB
        public let pattern: Pattern
        /// The system's name, printed on the band.
        public let label: String
    }

    public let material: Material
    /// The band printed on every front cover of the system.
    public let frontBand: Band
    /// A border around the front's art (the NES black box, the N64 frame); nil: art to the edge.
    public let frontFrame: RGB?
    /// The spine's colour; nil takes the colour of the game's cover edge (art printed around).
    public let spineColor: RGB?
    /// The band at the top of the spine, with the system's name.
    public let spineBand: Band
    /// Cardboard boxes carry a strip of the game's art down the spine, under the band.
    public let spineArt: Bool
    /// The colour of a case's plastic round its edges; nil for cardboard, whose printed art
    /// runs round the edges.
    public var plastic: RGB? = nil

    /// How round the box's edges are, as a share of its depth: a moulded case's edges are
    /// well rounded, a cardboard box's just softened, a jewel case's nearly square.
    public var edgeRounding: Double {
        switch material {
        case .plasticCase: return 0.45
        case .cardboard: return 0.14
        case .jewelCase: return 0.08
        }
    }

    /// The title on the spine reads in a colour that stands out on it.
    public func spineTitleIsLight(edge: RGB? = nil) -> Bool {
        (spineColor ?? edge ?? RGB(white: 0.2)).isDark
    }

    public static func of(_ system: SystemID) -> RetailPackage {
        let black = RGB(white: 0.07)
        switch system {
        case .nes:
            return RetailPackage(
                material: .cardboard,
                frontBand: Band(edge: .top, thickness: 0.16, color: black, pattern: .gridLines, label: "NES"),
                frontFrame: black,
                spineColor: black,
                spineBand: Band(edge: .top, thickness: 0.1, color: RGB(0.78, 0.12, 0.14), pattern: .plain, label: "NES"),
                spineArt: true
            )
        case .snes:
            return RetailPackage(
                material: .cardboard,
                frontBand: Band(edge: .bottom, thickness: 0.14, color: RGB(white: 0.58), pattern: .rule(RGB(0.42, 0.32, 0.62)), label: "SNES"),
                frontFrame: nil,
                spineColor: RGB(white: 0.22),
                spineBand: Band(edge: .top, thickness: 0.12, color: RGB(white: 0.58), pattern: .plain, label: "SNES"),
                spineArt: true
            )
        case .n64:
            return RetailPackage(
                material: .cardboard,
                frontBand: Band(edge: .top, thickness: 0.13, color: black, pattern: .colorBars, label: "N64"),
                frontFrame: black,
                spineColor: black,
                spineBand: Band(edge: .top, thickness: 0.12, color: black, pattern: .colorBars, label: "N64"),
                spineArt: true
            )
        case .gba:
            return RetailPackage(
                material: .cardboard,
                frontBand: Band(edge: .leading, thickness: 0.13, color: RGB(white: 0.1), pattern: .rule(RGB(0.42, 0.3, 0.75)), label: "GBA"),
                frontFrame: nil,
                spineColor: RGB(white: 0.1),
                spineBand: Band(edge: .top, thickness: 0.12, color: RGB(0.36, 0.24, 0.66), pattern: .plain, label: "GBA"),
                spineArt: true
            )
        case .atari7800:
            return RetailPackage(
                material: .cardboard,
                frontBand: Band(edge: .top, thickness: 0.14, color: RGB(white: 0.8), pattern: .rule(RGB(0.8, 0.14, 0.12)), label: "7800"),
                frontFrame: nil,
                spineColor: nil,
                spineBand: Band(edge: .top, thickness: 0.12, color: RGB(white: 0.8), pattern: .plain, label: "7800"),
                spineArt: true
            )
        case .nds:
            return RetailPackage(
                material: .plasticCase,
                frontBand: Band(edge: .top, thickness: 0.12, color: RGB(white: 0.95), pattern: .plain, label: "DS"),
                frontFrame: nil,
                spineColor: RGB(white: 0.93),
                spineBand: Band(edge: .top, thickness: 0.1, color: RGB(white: 0.78), pattern: .plain, label: "DS"),
                spineArt: false,
                plastic: RGB(white: 0.88)
            )
        case .psp:
            return RetailPackage(
                material: .plasticCase,
                frontBand: Band(edge: .top, thickness: 0.12, color: black, pattern: .plain, label: "PSP"),
                frontFrame: nil,
                spineColor: RGB(white: 0.95),
                spineBand: Band(edge: .top, thickness: 0.16, color: black, pattern: .plain, label: "PSP"),
                spineArt: false,
                plastic: RGB(white: 0.1)
            )
        case .ps1:
            return RetailPackage(
                material: .jewelCase,
                frontBand: Band(edge: .leading, thickness: 0.11, color: black, pattern: .plain, label: "PS1"),
                frontFrame: nil,
                spineColor: black,
                spineBand: Band(edge: .top, thickness: 0.14, color: RGB(white: 0.18), pattern: .plain, label: "PS1"),
                spineArt: false,
                plastic: RGB(white: 0.26)
            )
        case .genesis:
            return RetailPackage(
                material: .plasticCase,
                frontBand: Band(edge: .top, thickness: 0.17, color: black, pattern: .gridLines, label: "GENESIS"),
                frontFrame: nil,
                spineColor: black,
                spineBand: Band(edge: .top, thickness: 0.12, color: black, pattern: .rule(RGB(0.85, 0.12, 0.12)), label: "GENESIS"),
                spineArt: false,
                plastic: RGB(white: 0.08)
            )
        }
    }
}
