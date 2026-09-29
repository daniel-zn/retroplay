// SPDX-License-Identifier: GPL-3.0-or-later
import UIKit

/// Titles and identifiers shared by the Load button's UIMenu and its tests.
public enum PlayLoadMenuContent {
    public static let restartTitle = "Restart from Scratch"
    public static let importTitle = "Import Battery Save…"
    public static let emptyTitle = "No Save States"
    public static let restartIdentifier = UIAction.Identifier("retroplay.load.restart")
    public static let importIdentifier = UIAction.Identifier("retroplay.load.import")
    public static let emptyIdentifier = UIAction.Identifier("retroplay.load.empty")

    public static func entryIdentifier(slot: Int) -> UIAction.Identifier {
        UIAction.Identifier("retroplay.load.entry.\(slot)")
    }

    public static func title(for entry: SaveStateStore.Entry) -> String {
        let name = entry.slot == 0 ? "Latest Save" : "Previous Save \(entry.slot)"
        guard let date = entry.modifiedAt else { return name }
        return "\(name) — \(date.formatted(date: .abbreviated, time: .shortened))"
    }
}

/// UIKit Load control: tap quick-loads, long-press presents a `UIMenu`.
///
/// SwiftUI `Menu(primaryAction:)` on iOS 26 presents the rows but swallows their
/// actions (the row flashes and the closure never runs). `.buttonStyle(.borderless)`
/// on menu content has the same effect. `UIAction` handlers are the path that
/// actually runs. Tests invoke them with `UIMenuLeaf.performWithSender(_:target:)`.
@MainActor
public final class PlayLoadMenuButton: UIButton {
    public var onCommand: ((PlayLoadCommand) -> Void)?
    public var onImportSave: (() -> Void)?

    private var entries: [SaveStateStore.Entry] = []

    public override init(frame: CGRect) {
        super.init(frame: frame)
        // Matches the pause menu's SwiftUI tiles (MenuTileButtonStyle).
        var config = UIButton.Configuration.filled()
        config.baseBackgroundColor = UIColor.white.withAlphaComponent(0.12)
        config.baseForegroundColor = .white
        config.background.cornerRadius = 14
        config.cornerStyle = .fixed
        config.image = UIImage(systemName: "clock.arrow.circlepath")
        config.imagePadding = 6
        config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        config.title = "Load"
        configuration = config
        showsMenuAsPrimaryAction = false
        accessibilityLabel = "Load latest save"
        accessibilityHint = "Long-press for previous saves or Restart from Scratch"
        accessibilityIdentifier = "retroplay.load"
        addAction(UIAction { [weak self] _ in
            self?.onCommand?(.quickLoad)
        }, for: .touchUpInside)
        rebuildMenu()
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override var intrinsicContentSize: CGSize {
        let base = super.intrinsicContentSize
        return CGSize(width: max(base.width, 64), height: max(base.height, 32))
    }

    public func applyCaptionFont(_ font: UIFont) {
        guard var config = configuration else { return }
        config.title = "Load"
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = font
            return outgoing
        }
        configuration = config
        showsMenuAsPrimaryAction = false
        invalidateIntrinsicContentSize()
    }

    /// Rebuilds the long-press menu. Handlers read `onCommand` at tap time.
    public func setEntries(_ entries: [SaveStateStore.Entry]) {
        guard entries != self.entries else { return }
        self.entries = entries
        rebuildMenu()
    }

    /// Primary tap. Same event a finger-up sends to the button.
    public func invokePrimaryTap() {
        sendActions(for: .touchUpInside)
    }

    /// Menu-item tap. Same call UIKit makes when the row is chosen.
    @discardableResult
    public func invokeMenuAction(identifier: UIAction.Identifier) -> Bool {
        guard let menu else { return false }
        guard let action = Self.action(identifier: identifier, in: menu) else { return false }
        guard !action.attributes.contains(.disabled) else { return false }
        action.performWithSender(nil, target: nil)
        return true
    }

    public func menuActionAttributes(identifier: UIAction.Identifier) -> UIMenuElement.Attributes? {
        guard let menu, let action = Self.action(identifier: identifier, in: menu) else { return nil }
        return action.attributes
    }

    private func rebuildMenu() {
        var saveActions: [UIMenuElement] = []
        if entries.isEmpty {
            saveActions.append(UIAction(
                title: PlayLoadMenuContent.emptyTitle,
                identifier: PlayLoadMenuContent.emptyIdentifier,
                attributes: .disabled
            ) { _ in })
        } else {
            for entry in entries {
                let slot = entry.slot
                let captured = entry
                saveActions.append(UIAction(
                    title: PlayLoadMenuContent.title(for: entry),
                    identifier: PlayLoadMenuContent.entryIdentifier(slot: slot)
                ) { [weak self] _ in
                    self?.onCommand?(.loadEntry(captured))
                })
            }
        }

        let restart = UIAction(
            title: PlayLoadMenuContent.restartTitle,
            identifier: PlayLoadMenuContent.restartIdentifier,
            attributes: .destructive
        ) { [weak self] _ in
            self?.onCommand?(.restartFromScratch)
        }
        let importSave = UIAction(
            title: PlayLoadMenuContent.importTitle,
            identifier: PlayLoadMenuContent.importIdentifier
        ) { [weak self] _ in
            self?.onImportSave?()
        }

        menu = UIMenu(children: [
            UIMenu(options: .displayInline, children: saveActions),
            UIMenu(options: .displayInline, children: [restart]),
            UIMenu(options: .displayInline, children: [importSave]),
        ])
    }

    private static func action(identifier: UIAction.Identifier, in menu: UIMenu) -> UIAction? {
        for child in menu.children {
            if let action = child as? UIAction, action.identifier == identifier {
                return action
            }
            if let nested = child as? UIMenu, let found = action(identifier: identifier, in: nested) {
                return found
            }
        }
        return nil
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

        apply(.status("Restarting from scratch…"))
        apply(.refreshEntries)
        await bootFresh()
    }
}
