// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Names shown in the pause menu's Saves dropdown.
public enum PlaySavesMenuContent {
    public static let title = "Saves"
    public static let saveTitle = "Save"
    public static let resetTitle = "Reset"
    public static let importTitle = "Import Battery Save…"
    public static let emptyTitle = "No saves yet"

    public static func name(for entry: SaveStateStore.Entry) -> String {
        entry.slot == 0 ? "Latest Save" : "Previous Save \(entry.slot)"
    }
}

/// One execution path for every Load command. Rejections always produce a status effect.
@MainActor
public enum PlayLoadDriver {
    public struct Context {
        public var core: (any EmulatorCore)?
        public var saveBusy: Bool
        public var entries: [SaveStateStore.Entry]
        public var wasPaused: Bool
        public var pausedForBackground: Bool
        public var system: SystemID
        public var gameID: UUID
        public var paths: SavePaths
        public var fileManager: FileManager

        public init(
            core: (any EmulatorCore)?,
            saveBusy: Bool,
            entries: [SaveStateStore.Entry],
            wasPaused: Bool,
            pausedForBackground: Bool,
            system: SystemID,
            gameID: UUID,
            paths: SavePaths = SavePaths(),
            fileManager: FileManager = .default
        ) {
            self.core = core
            self.saveBusy = saveBusy
            self.entries = entries
            self.wasPaused = wasPaused
            self.pausedForBackground = pausedForBackground
            self.system = system
            self.gameID = gameID
            self.paths = paths
            self.fileManager = fileManager
        }
    }

    public enum Effect: Equatable {
        case status(String)
        case alert(String)
        case refreshEntries
        case setBusy(Bool)
    }

    public static func run(
        _ command: PlayLoadCommand,
        context: Context,
        apply: @escaping @MainActor (Effect) -> Void,
        bootFresh: @escaping @MainActor () async -> Void,
        shouldAbandon: @escaping @MainActor () -> Bool = { false }
    ) async {
        let resolved = SaveStateStore.resolvedEntries(
            system: context.system,
            gameID: context.gameID,
            paths: context.paths,
            fileManager: context.fileManager
        )
        var context = context
        context.entries = resolved

        let gate = PlayLoadReducer.gate(
            for: command,
            saveBusy: context.saveBusy,
            hasCore: context.core != nil,
            supportsSaveState: context.core?.supportsSaveState ?? false,
            hasSaveHistory: !resolved.isEmpty
        )
        guard gate == .execute else {
            let line = PlayLoadReducer.statusLine(for: gate) ?? "Couldn't complete load"
            apply(.status(line))
            NSLog("RP_LOAD rejected command=%@ status=%@", command.logName, line)
            return
        }

        if shouldAbandon() {
            NSLog("RP_LOAD abandon before start command=%@", command.logName)
            return
        }

        NSLog("RP_LOAD accepted command=%@", command.logName)
        switch command {
        case .quickLoad, .loadEntry:
            await load(command, context: context, apply: apply, shouldAbandon: shouldAbandon)
        case .restartFromScratch:
            await restart(context: context, apply: apply, bootFresh: bootFresh, shouldAbandon: shouldAbandon)
        }
    }

    private static func load(
        _ command: PlayLoadCommand,
        context: Context,
        apply: @escaping @MainActor (Effect) -> Void,
        shouldAbandon: @escaping @MainActor () -> Bool
    ) async {
        guard let entry = PlayLoadReducer.entry(for: command, entries: context.entries) else {
            apply(.status("No save state yet"))
            NSLog("RP_LOAD rejected command=%@ status=%@", command.logName, "No save state yet")
            return
        }
        guard let core = context.core else {
            apply(.status("Game is not running"))
            NSLog("RP_LOAD rejected command=%@ status=%@", command.logName, "Game is not running")
            return
        }

        apply(.setBusy(true))
        defer { apply(.setBusy(false)) }

        let outcome = await PlayLoadSession.load(
            entry: entry,
            core: core,
            wasPaused: context.wasPaused,
            pausedForBackground: context.pausedForBackground,
            fileManager: context.fileManager
        )
        if shouldAbandon() {
            NSLog("RP_LOAD abandon after load command=%@", command.logName)
            return
        }
        switch outcome {
        case .loaded(let line):
            apply(.status(line))
        case .missing:
            apply(.status("Save load failed"))
            apply(.alert(PlayLoadReducer.missingSaveMessage()))
            apply(.refreshEntries)
        case .failed(let message):
            apply(.status("Save load failed"))
            // Keep the file: a load can fail for reasons other than corruption (low
            // memory, a core hiccup), and the save may still be the player's only copy.
            apply(.alert(message))
            apply(.refreshEntries)
        case .cancelled:
            NSLog("RP_LOAD cancelled command=%@", command.logName)
        }
    }

    private static func restart(
        context: Context,
        apply: @escaping @MainActor (Effect) -> Void,
        bootFresh: @escaping @MainActor () async -> Void,
        shouldAbandon: @escaping @MainActor () -> Bool
    ) async {
        if context.saveBusy {
            apply(.status("Wait for save/load to finish"))
            return
        }
        guard let core = context.core else {
            apply(.status("Game is not running"))
            return
        }

        apply(.setBusy(true))
        defer { apply(.setBusy(false)) }

        let outcome = RestartFromScratch.prepare(
            core: core,
            operationInProgress: false,
            system: context.system,
            gameID: context.gameID,
            paths: context.paths,
            fileManager: context.fileManager
        )
        if shouldAbandon() {
            NSLog("RP_LOAD abandon after restart prepare")
            return
        }
        guard outcome.shouldBootFresh else {
            switch outcome {
            case .saveCleanupFailed:
                apply(.status("Restart failed"))
                apply(.alert(
                    "RetroPlay couldn't clear this game's save states. The current game is still running and was not restarted."
                ))
            case .ignored(let decision):
                switch decision {
                case .ignoreOperationInProgress:
                    apply(.status("Wait for save/load to finish"))
                case .ignoreNoActiveCore:
                    apply(.status("Game is not running"))
                case .restart:
                    apply(.status("Restart failed"))
                }
            case .ready:
                apply(.status("Restart failed"))
            }
            return
        }

        apply(.status("Resetting…"))
        apply(.refreshEntries)
        await bootFresh()
    }
}
