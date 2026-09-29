// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Loads a user-selected state without throwing or leaving a running game paused after failure.
public enum SaveStateLoader: Sendable {
    public enum Result: Equatable, Sendable {
        case loaded
        case missing
        case failed(String)
        /// The load task was cancelled (session leave or a newer command). Not a corrupt file.
        case cancelled
    }

    @MainActor
    public static func apply(
        core: any EmulatorCore,
        url: URL,
        resumeAfterLoad: Bool,
        fileManager: FileManager = .default
    ) async -> Result {
        guard fileManager.fileExists(atPath: url.path) else {
            return .missing
        }

        core.pause()
        do {
            try await core.loadState(from: url)
            if resumeAfterLoad { core.resume() }
            return .loaded
        } catch is CancellationError {
            return .cancelled
        } catch {
            if Task.isCancelled {
                return .cancelled
            }
            if resumeAfterLoad { core.resume() }
            NSLog("RP_LOAD_STATE failed path=%@ error=%@", url.path, String(describing: error))
            return .failed(error.localizedDescription)
        }
    }
}
