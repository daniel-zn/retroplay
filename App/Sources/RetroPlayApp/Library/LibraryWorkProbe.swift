// SPDX-License-Identifier: GPL-3.0-or-later
#if DEBUG
import SwiftUI
import UIKit

/// Debug builds only: how much the library does while it moves, for UI tests to compare (a
/// pull down in the grid and in Cover Flow). Frames that came late (the main thread busy past a
/// refresh), and how often the library's views were evaluated again. Shown to the tests as the
/// value of the `library.work` element, read every quarter second.
@MainActor
enum LibraryWorkProbe {
    static var library = 0
    static var coverFlow = 0
    static var carousel = 0
    static var covers = 0
    static var stage = 0

    static var summary: String {
        "frames=\(FramePacer.shared.frames) late=\(FramePacer.shared.late) library=\(library) "
            + "coverFlow=\(coverFlow) carousel=\(carousel) covers=\(covers) stage=\(stage)"
    }

    /// Counts the display's frames, and those that came more than half a refresh late.
    @MainActor
    final class FramePacer: NSObject {
        static let shared = FramePacer()
        private(set) var frames = 0
        private(set) var late = 0
        private var link: CADisplayLink?
        private var last: CFTimeInterval = 0

        func start() {
            guard link == nil else { return }
            let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
            link.add(to: .main, forMode: .common)
            self.link = link
        }

        @objc private func tick(_ link: CADisplayLink) {
            defer { last = link.timestamp }
            guard last > 0 else { return }
            frames += 1
            if link.timestamp - last > link.duration * 1.5 { late += 1 }
        }
    }
}

extension View {
    /// The probe's numbers on an invisible element (`library.work`).
    func libraryWorkProbe() -> some View {
        overlay(alignment: .topLeading) {
            TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                Text(".")
                    .font(.system(size: 2))
                    .opacity(0.02)
                    .accessibilityIdentifier("library.work")
                    .accessibilityValue(LibraryWorkProbe.summary)
            }
            .allowsHitTesting(false)
            .onAppear { LibraryWorkProbe.FramePacer.shared.start() }
        }
    }
}
#endif
