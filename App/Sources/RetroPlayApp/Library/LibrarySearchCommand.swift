// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI

/// What the Search Library command does: the library publishes it while it's in front
/// (`focusedSceneValue`), and the command is greyed out otherwise.
struct RetroPlaySearchAction {
    let perform: () -> Void

    func callAsFunction() { perform() }
}

extension FocusedValues {
    @Entry var retroPlaySearchLibrary: RetroPlaySearchAction?
}

/// The app's keyboard commands, in iPadOS's menu bar and the Command-key overlay: Search Library
/// (Command-F) puts the cursor in the library's search field.
public struct RetroPlayCommands: Commands {
    @FocusedValue(\.retroPlaySearchLibrary) private var searchLibrary

    public init() {}

    public var body: some Commands {
        CommandMenu("Library") {
            Button("Search Library") { searchLibrary?() }
                .keyboardShortcut("f", modifiers: .command)
                .disabled(searchLibrary == nil)
        }
    }
}
