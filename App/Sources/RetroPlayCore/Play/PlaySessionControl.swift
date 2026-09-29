// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

public enum PlaybackControlState: Equatable, Sendable {
    case running
    case paused

    public enum Action: Equatable, Sendable {
        case pause
        case resume
    }

    public var action: Action {
        switch self {
        case .running: return .pause
        case .paused: return .resume
        }
    }

    public var accessibilityLabel: String {
        switch self {
        case .running: return "Pause"
        case .paused: return "Resume"
        }
    }

    public var statusLine: String {
        switch self {
        case .running: return "Running"
        case .paused: return "Paused"
        }
    }

    public mutating func toggle() {
        self = self == .running ? .paused : .running
    }
}

/// Whether emulation should resume after save/load/auto-resume while scene-driven background pause is active.
public enum PlaybackResumePolicy: Sendable {
    public static func shouldResumeAfterOperation(
        userPaused: Bool,
        pausedForBackground: Bool
    ) -> Bool {
        !userPaused && !pausedForBackground
    }
}

/// Testable restart preparation. PlayView always boots with auto-resume disabled after `.ready`.
public enum RestartFromScratch: Sendable {
    public enum Decision: Equatable, Sendable {
        case restart
        case ignoreNoActiveCore
        case ignoreOperationInProgress
    }

    public enum Outcome: Equatable, Sendable {
        case ready
        case saveCleanupFailed
        case ignored(Decision)

        public var shouldBootFresh: Bool {
            switch self {
            case .ready: return true
            case .saveCleanupFailed, .ignored: return false
            }
        }
    }

    public static func decide(hasActiveCore: Bool, operationInProgress: Bool) -> Decision {
        guard !operationInProgress else { return .ignoreOperationInProgress }
        guard hasActiveCore else { return .ignoreNoActiveCore }
        return .restart
    }

    @MainActor
    public static func prepare(
        core: (any EmulatorCore)?,
        operationInProgress: Bool,
        system: SystemID,
        gameID: UUID,
        paths: SavePaths = SavePaths(),
        fileManager: FileManager = .default
    ) -> Outcome {
        let decision = decide(hasActiveCore: core != nil, operationInProgress: operationInProgress)
        guard decision == .restart, let core else {
            return .ignored(decision)
        }

        // Pause before touching on-disk states so the emu loop cannot race quick-save I/O.
        core.pause()
        do {
            try SaveStateStore.removeAllSaves(
                system: system,
                gameID: gameID,
                paths: paths,
                fileManager: fileManager
            )
            core.stop()
            return .ready
        } catch {
            // Stay paused: the pause menu is still open, and closing it resumes the game.
            NSLog(
                "RP_RESTART save cleanup failed system=%@ game=%@ error=%@",
                system.rawValue,
                gameID.uuidString,
                String(describing: error)
            )
            return .saveCleanupFailed
        }
    }
}

/// User intent from the Load control (tap = quick load; long-press menu = other cases).
public enum PlayLoadCommand: Equatable, Sendable {
    case quickLoad
    case loadEntry(SaveStateStore.Entry)
    case restartFromScratch

    public var logName: String {
        switch self {
        case .quickLoad:
            return "quickLoad"
        case .loadEntry(let entry):
            return "loadEntry slot=\(entry.slot)"
        case .restartFromScratch:
            return "restartFromScratch"
        }
    }
}

/// Whether PlayView should run the requested load command now.
public enum PlayLoadCommandGate: Equatable, Sendable {
    case execute
    case ignoreBusy
    case ignoreNoCore
    case ignoreSaveStatesUnavailable
    case ignoreNoQuickSave
}

public enum PlayLoadReducer: Sendable {
    public static func gate(
        for command: PlayLoadCommand,
        saveBusy: Bool,
        hasCore: Bool,
        supportsSaveState: Bool,
        hasSaveHistory: Bool
    ) -> PlayLoadCommandGate {
        if saveBusy { return .ignoreBusy }
        switch command {
        case .restartFromScratch:
            return hasCore ? .execute : .ignoreNoCore
        case .quickLoad:
            guard hasCore else { return .ignoreNoCore }
            guard supportsSaveState else { return .ignoreSaveStatesUnavailable }
            return hasSaveHistory ? .execute : .ignoreNoQuickSave
        case .loadEntry:
            guard hasCore else { return .ignoreNoCore }
            guard supportsSaveState else { return .ignoreSaveStatesUnavailable }
            return .execute
        }
    }

    public static func entry(
        for command: PlayLoadCommand,
        entries: [SaveStateStore.Entry]
    ) -> SaveStateStore.Entry? {
        switch command {
        case .quickLoad:
            return entries.first
        case .loadEntry(let entry):
            return entry
        case .restartFromScratch:
            return nil
        }
    }

    public static func statusLine(for gate: PlayLoadCommandGate) -> String? {
        switch gate {
        case .execute:
            return nil
        case .ignoreBusy:
            return "Wait for save/load to finish"
        case .ignoreNoCore:
            return "Game is not running"
        case .ignoreSaveStatesUnavailable:
            return "Save states not available"
        case .ignoreNoQuickSave:
            return "No save state yet"
        }
    }

    public static func loadStatusLine(for entry: SaveStateStore.Entry) -> String {
        entry.slot == 0 ? "Quick load OK" : "Loaded previous save \(entry.slot)"
    }

    public static func missingSaveMessage() -> String {
        "That save state is no longer available."
    }
}

/// Serializes Load commands onto one MainActor handler.
///
/// The handler runs on a task this object owns. It is not a child of the caller, so a
/// SwiftUI menu dismissal or view update cannot cancel an accepted load. `cancel()` is
/// only for leaving the session (or `submit` of a newer command, which supersedes).
@MainActor
public final class PlayLoadActionCoordinator {
    public private(set) var lastSubmittedCommand: PlayLoadCommand?
    public private(set) var submissionCount = 0
    private var activeTicket = 0
    private var inFlight: Task<Void, Never>?

    public init() {}

    public func isCurrent(_ ticket: Int) -> Bool {
        ticket == activeTicket
    }

    public func submit(
        _ command: PlayLoadCommand,
        handler: @MainActor @escaping (PlayLoadCommand) async -> Void
    ) {
        submit(command) { command, _ in
            await handler(command)
        }
    }

    /// `stillCurrent` is false after `cancel()` or a newer `submit`, and stays true across menu dismissal.
    public func submit(
        _ command: PlayLoadCommand,
        handler: @MainActor @escaping (
            PlayLoadCommand,
            @escaping @MainActor () -> Bool
        ) async -> Void
    ) {
        activeTicket += 1
        let ticket = activeTicket
        lastSubmittedCommand = command
        submissionCount += 1
        inFlight?.cancel()
        inFlight = Task { @MainActor in
            await self.deliver(command, ticket: ticket, handler: handler)
        }
    }

    private func deliver(
        _ command: PlayLoadCommand,
        ticket: Int,
        handler: @MainActor @escaping (
            PlayLoadCommand,
            @escaping @MainActor () -> Bool
        ) async -> Void
    ) async {
        guard isCurrent(ticket) else { return }
        let stillCurrent: @MainActor () -> Bool = { self.isCurrent(ticket) }
        await handler(command, stillCurrent)
    }

    /// Invalidates the accepted command. Call when leaving the game, not when a menu closes.
    public func cancel() {
        activeTicket += 1
        inFlight?.cancel()
        inFlight = nil
    }
}

@MainActor
public enum PlayLoadSession: Sendable {
    public enum LoadOutcome: Equatable, Sendable {
        case loaded(statusLine: String)
        case missing
        case failed(message: String)
        case cancelled
    }

    public static func load(
        entry: SaveStateStore.Entry,
        core: any EmulatorCore,
        wasPaused: Bool,
        pausedForBackground: Bool = false,
        fileManager: FileManager = .default
    ) async -> LoadOutcome {
        let result = await SaveStateLoader.apply(
            core: core,
            url: entry.url,
            resumeAfterLoad: PlaybackResumePolicy.shouldResumeAfterOperation(
                userPaused: wasPaused,
                pausedForBackground: pausedForBackground
            ),
            fileManager: fileManager
        )
        switch result {
        case .loaded:
            return .loaded(statusLine: PlayLoadReducer.loadStatusLine(for: entry))
        case .missing:
            return .missing
        case .failed(let message):
            return .failed(message: message)
        case .cancelled:
            return .cancelled
        }
    }
}

/// Soft reboot after importing a battery save without touching host quick-states under `States/`.
public enum BatterySaveReload: Sendable {
    /// Matches PlayView `leavePlay` — long enough for a quick-save/load to finish cleanly.
    public static let saveBusyPollNanoseconds: UInt64 = 50_000_000
    public static let saveBusyMaxPollAttempts = 40

    public static func shouldReloadAfterImport(for system: SystemID) -> Bool {
        switch system {
        case .gba, .psp, .nds:
            return true
        case .n64:
            return true
        }
    }

    public static func reloadNotice(for system: SystemID) -> String? {
        guard shouldReloadAfterImport(for: system) else { return nil }
        return "Reloading to apply imported battery save…"
    }

    /// Battery-save reload must not race an in-flight quick-save/load or abandon silently.
    @MainActor
    public static func waitForSaveIdle(
        isSaveBusy: @escaping @MainActor () -> Bool,
        sleep: @escaping @Sendable (UInt64) async throws -> Void = { try await Task.sleep(nanoseconds: $0) }
    ) async -> Bool {
        for _ in 0..<saveBusyMaxPollAttempts where isSaveBusy() {
            do {
                try await sleep(saveBusyPollNanoseconds)
            } catch {
                return false
            }
        }
        return !isSaveBusy()
    }

    public static let saveIdleTimeoutNotice =
        "Import saved, but reload timed out while a save was in progress. Stop and relaunch the game to apply it."
}

/// Auto-save on leaving Play must not race an in-flight quick-save/load.
public enum LeavePlayPolicy: Sendable {
    public static func shouldAutoSaveAfterWaiting(saveStillBusy: Bool) -> Bool {
        !saveStillBusy
    }
}
