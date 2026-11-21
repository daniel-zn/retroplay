// SPDX-License-Identifier: GPL-3.0-or-later
import Combine
import RetroPlayCore
import UIKit

/// `UIApplication.beginBackgroundTask`, ended once: by the owner, or when iOS ends the
/// background time (after `onExpiry`, which then has a moment to wind its work down).
@MainActor
final class BackgroundTask {
    private var id = UIBackgroundTaskIdentifier.invalid

    init(name: String, onExpiry: (() -> Void)? = nil) {
        id = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            MainActor.assumeIsolated {
                guard let onExpiry else { self?.end(); return }
                onExpiry()
                // The owner ends it once the work has stopped; this is the backstop.
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(1))
                    self?.end()
                }
            }
        }
    }

    func end() {
        guard id != .invalid else { return }
        UIApplication.shared.endBackgroundTask(id)
        id = .invalid
    }
}

/// Keeps the app running while games copy in, so switching apps mid-import doesn't suspend
/// it inside a file coordinator's read of a provider's file (an SMB share's, iCloud
/// Drive's), which iOS ends the app for. When iOS ends the background time first, the
/// imports stop cleanly (their partial copies removed) and say why when the app is back.
@MainActor
final class ImportBackgroundTime {
    private var task: BackgroundTask?
    private var watch: AnyCancellable?

    init(_ store: LibraryStore) {
        watch = store.$importsInProgress
            .map { $0 > 0 }
            .removeDuplicates()
            .sink { [weak self, weak store] running in
                // The store publishes on the main actor.
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if running {
                        self.task = BackgroundTask(name: "RetroPlay.ImportGames") {
                            store?.imports.stopAll(reason: "It stopped when RetroPlay was in the background for too long. Import it again.")
                        }
                    } else {
                        self.task?.end()
                        self.task = nil
                    }
                }
            }
    }
}
