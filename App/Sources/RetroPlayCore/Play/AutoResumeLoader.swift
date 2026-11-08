// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Decides whether re-entering Play for a game should transparently resume from the
/// existing quick save (written on Back/leave) before normal play starts.
///
/// A missing quick save is a normal first-run path, never an error. A load failure must
/// never trap navigation or crash — it only prevents resume, and play continues fresh.
public enum AutoResumeLoader: Sendable {
    public enum Decision: Equatable, Sendable {
        /// A quick save exists and the core can load it — attempt the load.
        case attemptLoad
        /// No quick save yet, or the core cannot load states — proceed as first run.
        case firstRun
    }

    public enum Status: Equatable, Sendable {
        case loaded
        case firstRun
        case failed
        /// Session was superseded (user left Play) before load could run — not a corrupt save.
        case cancelled
    }

    public static func decide(hasSaveHistory: Bool, supportsSaveState: Bool) -> Decision {
        (hasSaveHistory && supportsSaveState) ? .attemptLoad : .firstRun
    }

    /// Human-readable Play status line for each outcome. Never implies a crash or a trap.
    public static func statusLine(for status: Status) -> String {
        switch status {
        case .loaded: return "Resumed from quick save"
        case .firstRun: return "Waiting for first frame…"
        case .failed: return "Auto-load failed — starting fresh"
        case .cancelled: return "Waiting for first frame…"
        }
    }

    /// Attempts the resume for a live core, using the existing quick-save path. Never throws:
    /// callers get a `Status` and continue play regardless (missing/failed both fall through to
    /// normal boot, matching the "never trap navigation" requirement).
    @MainActor
    public static func apply(
        core: any EmulatorCore,
        system: SystemID,
        gameID: UUID,
        paths: SavePaths = SavePaths(),
        fileManager: FileManager = .default,
        resumeAfterLoad: Bool = true,
        notBefore: Date? = nil,
        shouldContinue: @escaping @MainActor () -> Bool = { true }
    ) async -> Status {
        // `notBefore`: saves were imported then (FreshBoot); older states hold the old save.
        let entries = SaveStateStore.resolvedEntries(
            system: system,
            gameID: gameID,
            paths: paths,
            fileManager: fileManager
        ).filter { entry in
            notBefore.map { (entry.modifiedAt ?? .distantPast) > $0 } ?? true
        }
        guard !entries.isEmpty else {
            return .firstRun
        }
        guard decide(hasSaveHistory: true, supportsSaveState: core.supportsSaveState) == .attemptLoad else {
            return .firstRun
        }

        core.pause()
        defer {
            if resumeAfterLoad { core.resume() }
        }

        for entry in entries {
            guard shouldContinue() else { return .cancelled }
            let result = await SaveStateLoader.apply(
                core: core,
                url: entry.url,
                resumeAfterLoad: false,
                fileManager: fileManager
            )
            switch result {
            case .loaded:
                return .loaded
            case .missing:
                continue
            case .cancelled:
                return .cancelled
            case .failed:
                // Keep the file: a failure can be temporary or come from a core update, and
                // the slot rotates out as new saves are written. Try the next one.
                NSLog(
                    "RP_AUTORESUME skipped unloadable save system=%@ game=%@ path=%@",
                    system.rawValue,
                    gameID.uuidString,
                    entry.url.path
                )
            }
        }

        NSLog(
            "RP_AUTORESUME load failed system=%@ game=%@",
            system.rawValue,
            gameID.uuidString
        )
        return .failed
    }
}
