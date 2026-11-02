// SPDX-License-Identifier: GPL-3.0-or-later
#if DEBUG
import SwiftUI
import UIKit

/// Debug builds only: what VoiceOver can reach on screen, found the way it walks the window —
/// hidden views and elements hidden from accessibility left out, a modal view's siblings left
/// out, a container's elements in place of its subviews. UI tests read it from the
/// "a11y.probe" element (`-RetroPlaySmokeAccessibilityProbe YES`), since XCUITest's own tree
/// can list elements VoiceOver doesn't reach.
@MainActor
enum AccessibilityProbe {
    static func reachableLabels() -> [String] {
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first else { return [] }
        var labels: [String] = []
        walk(window, into: &labels, depth: 0)
        return labels
    }

    private static func children(of object: NSObject) -> [NSObject] {
        if let elements = object.accessibilityElements as? [NSObject] { return elements }
        let count = object.accessibilityElementCount()
        if count != NSNotFound, count > 0 {
            return (0..<count).compactMap { object.accessibilityElement(at: $0) as? NSObject }
        }
        return (object as? UIView)?.subviews ?? []
    }

    private static func walk(_ object: NSObject, into labels: inout [String], depth: Int) {
        guard depth < 80 else { return }
        if let view = object as? UIView, view.isHidden || view.alpha < 0.01 { return }
        if object.accessibilityElementsHidden { return }
        if object.isAccessibilityElement {
            if let label = object.accessibilityLabel, !label.isEmpty { labels.append(label) }
            return
        }
        var items = children(of: object)
        // A modal view hides its siblings from VoiceOver.
        if let modal = items.last(where: { $0.accessibilityViewIsModal }) { items = [modal] }
        for item in items { walk(item, into: &labels, depth: depth + 1) }
    }
}

/// The probe's result, published once the smoke-opened pause menu is up.
struct AccessibilityProbeOverlay: View {
    @State private var result = ""

    var body: some View {
        Text(verbatim: result)
            .font(.system(size: 1))
            .opacity(0.02)
            .allowsHitTesting(false)
            .accessibilityIdentifier("a11y.probe")
            .task {
                // The smoke menu opens about 5 s after the game starts; looked at after that.
                try? await Task.sleep(for: .seconds(12))
                result = "PROBE|" + AccessibilityProbe.reachableLabels().joined(separator: "|")
            }
    }
}
#endif
