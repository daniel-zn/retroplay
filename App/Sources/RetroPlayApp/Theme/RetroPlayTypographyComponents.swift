// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI

/// The system's empty state, in the app's fonts with the title glitch.
struct RetroPlayUnavailableView: View {
    let title: String
    let systemImage: String
    let description: String

    var body: some View {
        ContentUnavailableView {
            Label {
                Text(title)
                    .font(RetroPlayFont.titleFace(.title3))
                    .retroPlayTitleGlitch(title)
            } icon: {
                Image(systemName: systemImage)
            }
        } description: {
            Text(description)
                .font(RetroPlayFont.body)
        }
    }
}
