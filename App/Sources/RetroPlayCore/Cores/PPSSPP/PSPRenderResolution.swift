// SPDX-License-Identifier: GPL-3.0-or-later
import CoreGraphics
import Foundation

/// The PSP's internal resolution: PPSSPP renders 3D at a multiple of the PSP's 480 × 272.
/// Auto matches the picture as it is shown (its size on screen in pixels, on the largest
/// screen showing it), rounded to the nearest multiple.
public enum PSPRenderResolution: Int, CaseIterable, Sendable, Identifiable {
    case auto = 0
    case native = 1
    case double = 2
    case triple = 3

    /// `UserDefaults` key (an `Int`, the raw value).
    public static let defaultsKey = "retroplay.psp.resolution"

    public static let nativeSize = CGSize(width: 480, height: 272)
    /// Auto never goes past this (2400 × 1360): above that the picture can't get sharper on a
    /// phone or a 1080p TV, and every multiple costs GPU time and memory squared.
    public static let autoMaximumScale = 5
    /// Before any screen reports a size.
    public static let autoFallbackScale = 2

    public var id: Int { rawValue }

    public var title: String {
        switch self {
        case .auto: "Auto"
        case .native: "1×"
        case .double: "2×"
        case .triple: "3×"
        }
    }

    public var accessibilityTitle: String {
        switch self {
        case .auto: "Automatic, matches the screen"
        case .native: "Native, 480 by 272"
        case .double: "2 times native"
        case .triple: "3 times native"
        }
    }

    /// The setting saved in `defaults` (Auto if unset or unknown).
    public static func current(_ defaults: UserDefaults = .standard) -> PSPRenderResolution {
        PSPRenderResolution(rawValue: defaults.integer(forKey: defaultsKey)) ?? .auto
    }

    /// The multiple of 480 × 272 to render at when the picture is `displayPixels` large.
    public func scale(forDisplayPixels displayPixels: CGSize) -> Int {
        guard self == .auto else { return rawValue }
        guard displayPixels.width > 0, displayPixels.height > 0 else { return Self.autoFallbackScale }
        // Whichever axis the picture is stretched more along (fill mode crops the other).
        let ratio = max(displayPixels.width / Self.nativeSize.width, displayPixels.height / Self.nativeSize.height)
        return min(Self.autoMaximumScale, max(1, Int(ratio.rounded())))
    }
}
