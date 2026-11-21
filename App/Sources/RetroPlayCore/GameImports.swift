// SPDX-License-Identifier: GPL-3.0-or-later
import Combine
import Foundation

/// The games `LibraryStore.importInBackground` is copying in, for the library's import
/// status: each pick, how far its copy is, how it ended, and a cancel. Its own object, so a
/// copy's progress redraws only the status, not the library.
@MainActor
public final class GameImports: ObservableObject {
    public enum State: Equatable, Sendable {
        case waiting
        case copying
        case done
        case failed(String)
        case cancelled
    }

    public struct Item: Identifiable, Equatable, Sendable {
        public let id: UUID
        public let name: String
        public fileprivate(set) var copied: Int64 = 0
        /// The file's size (all of a disc's files), when its provider reports one.
        public fileprivate(set) var total: Int64?
        public fileprivate(set) var state: State = .waiting

        public var isRunning: Bool { state == .waiting || state == .copying }

        /// 0…1 when the size is known.
        public var fraction: Double? {
            guard let total, total > 0 else { return nil }
            return min(1, Double(copied) / Double(total))
        }
    }

    /// This round of imports: the ones running and the ones that ended since the last round
    /// began (cleared when an import starts with none running).
    @Published public private(set) var items: [Item] = []
    private var cancellations: [UUID: ImportCancellation] = [:]
    /// Imports stopped by `stopAll`, with why (the player's own cancels aren't here).
    private(set) var stopReasons: [UUID: String] = [:]

    public init() {}

    public var isRunning: Bool { items.contains(where: \.isRunning) }

    /// The player's cancel: the copy stops and leaves nothing behind.
    public func cancel(_ id: UUID) {
        cancellations[id]?.cancel()
    }

    /// Stops every running import (iOS is ending the app's background time); each ends as
    /// failed, with `reason`.
    public func stopAll(reason: String) {
        for item in items where item.isRunning {
            stopReasons[item.id] = reason
            cancellations[item.id]?.cancel()
        }
    }

    func begin(_ jobs: [LibraryStore.ImportJob]) -> LibraryStore.ImportControl {
        if !isRunning {
            items.removeAll()
            stopReasons.removeAll()
        }
        var control = LibraryStore.ImportControl()
        for job in jobs {
            let cancellation = ImportCancellation()
            cancellations[job.id] = cancellation
            control.cancellations[job.id] = cancellation
            items.append(Item(id: job.id, name: job.originalName))
        }
        control.progress = { [weak self] id, copied, total in
            Task { @MainActor in self?.update(id, copied: copied, total: total) }
        }
        return control
    }

    private func update(_ id: UUID, copied: Int64, total: Int64?) {
        guard let index = items.firstIndex(where: { $0.id == id }), items[index].isRunning else { return }
        items[index].state = .copying
        items[index].copied = copied
        items[index].total = total
    }

    func finish(_ id: UUID, _ state: State) {
        cancellations[id] = nil
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].state = state
        if state == .done, let total = items[index].total { items[index].copied = total }
    }
}
