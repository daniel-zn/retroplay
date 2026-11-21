// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
@testable import RetroPlayCore

/// Import batches: one bad file must not cancel the rest, and the same game picked twice (in
/// one pick, in overlapping picks, or straight from Games/) must be added only once.
@MainActor
final class LibraryImportBatchTests: XCTestCase {
    private let fm = FileManager.default
    private lazy var root: URL = {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("rp-import-batch-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }()

    private func inboxFile(_ name: String, _ contents: String = "not-a-copyrighted-rom") throws -> URL {
        let dir = root.appendingPathComponent("inbox-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        try Data(contents.utf8).write(to: url)
        return url
    }

    /// A pick whose file cannot be read (gone, or never downloaded).
    private func unreadableFile(_ name: String) -> URL {
        root.appendingPathComponent("gone-\(UUID().uuidString)", isDirectory: true).appendingPathComponent(name)
    }

    /// Everything in Games/, hidden files included, so a leftover partial copy shows up.
    private func gamesFolderContents(_ store: LibraryStore) throws -> [String] {
        try fm.contentsOfDirectory(atPath: store.gamesDirectoryURL.path).sorted()
    }

    // MARK: - One bad file (1)

    func testOneUnreadableFileDoesNotCancelTheBatch() throws {
        let store = LibraryStore(fileManager: fm, documentsDirectoryURL: root)
        let good = try inboxFile("Good.gba", "gba")
        let alsoGood = try inboxFile("Other.z64", "n64")

        let summary = try store.importSummary(from: [good, unreadableFile("Missing.nds"), alsoGood])

        XCTAssertEqual(summary.added.map(\.relativePath), ["Good.gba", "Other.z64"])
        XCTAssertEqual(summary.failed.map(\.fileName), ["Missing.nds"])
        XCTAssertFalse(try XCTUnwrap(summary.failed.first).reason.isEmpty)
        XCTAssertTrue(summary.duplicates.isEmpty)
        XCTAssertEqual(store.games.count, 2)
        XCTAssertEqual(try gamesFolderContents(store), ["Good.gba", "Other.z64"])

        let reloaded = LibraryStore(fileManager: fm, documentsDirectoryURL: root)
        XCTAssertEqual(Set(reloaded.games.map(\.relativePath)), ["Good.gba", "Other.z64"])
    }

    func testBackgroundImportKeepsGoodFilesWhenOneFails() async throws {
        let store = LibraryStore(fileManager: fm, documentsDirectoryURL: root)
        let good = try inboxFile("Good.gba")

        let summary = try await store.importInBackground(from: [unreadableFile("Missing.nds"), good])

        XCTAssertEqual(summary.added.map(\.relativePath), ["Good.gba"])
        XCTAssertEqual(summary.failed.map(\.fileName), ["Missing.nds"])
        XCTAssertEqual(store.games.map(\.relativePath), ["Good.gba"])
        XCTAssertEqual(store.importsInProgress, 0)
        XCTAssertEqual(try gamesFolderContents(store), ["Good.gba"])

        // The failed pick's name was not kept reserved: a readable copy imports under it.
        let retry = try await store.importInBackground(from: [inboxFile("Missing.nds", "nds")])
        XCTAssertEqual(retry.added.map(\.relativePath), ["Missing.nds"])
        XCTAssertTrue(retry.failed.isEmpty)
    }

    // MARK: - Duplicates within and across batches (2)

    func testSameGamePickedTwiceInOneBatchIsAddedOnce() throws {
        let store = LibraryStore(fileManager: fm, documentsDirectoryURL: root)
        let first = try inboxFile("Zelda.gba", "same-bytes")
        let sameNameElsewhere = try inboxFile("Zelda.gba", "same-bytes")
        let renamedCopy = try inboxFile("Zelda (copy).gba", "same-bytes")

        let summary = try store.importSummary(from: [first, first, sameNameElsewhere, renamedCopy])

        XCTAssertEqual(summary.added.map(\.relativePath), ["Zelda.gba"])
        XCTAssertEqual(summary.duplicates, ["Zelda.gba", "Zelda.gba", "Zelda (copy).gba"])
        XCTAssertEqual(store.games.count, 1)
        XCTAssertEqual(try gamesFolderContents(store), ["Zelda.gba"])
    }

    func testDifferentGamesWithOneNameInOneBatchAreBothAdded() throws {
        let store = LibraryStore(fileManager: fm, documentsDirectoryURL: root)
        let summary = try store.importSummary(from: [
            inboxFile("Zelda.gba", "version-one"),
            inboxFile("Zelda.gba", "version-two!"),
        ])

        XCTAssertEqual(summary.added.map(\.relativePath), ["Zelda.gba", "Zelda-1.gba"])
        XCTAssertTrue(summary.duplicates.isEmpty)
    }

    func testOverlappingImportsOfTheSameGameAddItOnce() async throws {
        let store = LibraryStore(fileManager: fm, documentsDirectoryURL: root)
        let first = try inboxFile("Zelda.gba", "same-bytes")
        let second = try inboxFile("Zelda.gba", "same-bytes")

        // The second pick starts before the first batch has committed its row.
        let a = Task { try await store.importInBackground(from: [first]) }
        let b = Task { try await store.importInBackground(from: [second]) }
        let results = [try await a.value, try await b.value]

        XCTAssertEqual(results.flatMap(\.added).map(\.relativePath), ["Zelda.gba"])
        XCTAssertEqual(results.flatMap(\.duplicates), ["Zelda.gba"])
        XCTAssertEqual(store.games.count, 1)
        XCTAssertEqual(store.importsInProgress, 0)
        XCTAssertEqual(try gamesFolderContents(store), ["Zelda.gba"])
    }

    func testPickFromGamesFolderIsNotCopiedNextToItself() async throws {
        let store = LibraryStore(fileManager: fm, documentsDirectoryURL: root)
        let game = try XCTUnwrap(store.importFiles(from: [inboxFile("Zelda.gba")]).first)

        let again = try await store.importInBackground(from: [store.absoluteURL(for: game)])
        XCTAssertTrue(again.added.isEmpty)
        XCTAssertEqual(again.duplicates, ["Zelda.gba"])

        // Dropped in through Files and picked before a folder scan ran: the scan adds it as is.
        let dropped = store.gamesDirectoryURL.appendingPathComponent("Dropped.nds")
        try Data("nds".utf8).write(to: dropped)
        let picked = try await store.importInBackground(from: [dropped])
        XCTAssertTrue(picked.added.isEmpty)
        XCTAssertTrue(picked.failed.isEmpty)
        XCTAssertEqual(Set(store.games.map(\.relativePath)), ["Zelda.gba", "Dropped.nds"])
        XCTAssertEqual(try gamesFolderContents(store), ["Dropped.nds", "Zelda.gba"])
    }
    // MARK: - Stopped copies (3)

    /// A picked file big enough to copy in several megabyte chunks, slowed down so it can be
    /// stopped mid-copy.
    private func slowImport(_ store: LibraryStore) throws -> Task<LibraryImportSummary, Error> {
        let big = root.appendingPathComponent("inbox-big", isDirectory: true).appendingPathComponent("Big.gba")
        try fm.createDirectory(at: big.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(count: 6 << 20).write(to: big)
        LibraryStore.testChunkPause = 0.1
        addTeardownBlock { LibraryStore.testChunkPause = 0 }
        return Task { try await store.importInBackground(from: [big]) }
    }

    /// Waits until the copy has written a chunk.
    private func waitForCopy(_ store: LibraryStore) async throws {
        for _ in 0..<100 where store.imports.items.first?.copied ?? 0 == 0 {
            try await Task.sleep(for: .milliseconds(20))
        }
        let item = try XCTUnwrap(store.imports.items.first)
        XCTAssertEqual(item.state, .copying)
        XCTAssertEqual(item.total, 6 << 20)
        XCTAssertGreaterThan(item.copied, 0)
    }

    func testCancelledCopyLeavesNothingBehind() async throws {
        let store = LibraryStore(fileManager: fm, documentsDirectoryURL: root)
        let task = try slowImport(store)
        try await waitForCopy(store)
        XCTAssertTrue(store.imports.isRunning)

        store.imports.cancel(try XCTUnwrap(store.imports.items.first).id)
        let summary = try await task.value

        XCTAssertEqual(summary.cancelled, ["Big.gba"])
        XCTAssertTrue(summary.added.isEmpty)
        XCTAssertTrue(summary.failed.isEmpty)
        XCTAssertTrue(store.games.isEmpty)
        XCTAssertEqual(store.importsInProgress, 0)
        XCTAssertEqual(store.imports.items.map(\.state), [.cancelled])
        XCTAssertEqual(try gamesFolderContents(store), [], "a partial copy is left in Games/")
    }

    /// iOS ending the background time stops every copy; each is a failure that says why.
    func testStoppedCopyFailsWithTheReason() async throws {
        let store = LibraryStore(fileManager: fm, documentsDirectoryURL: root)
        let task = try slowImport(store)
        try await waitForCopy(store)

        store.imports.stopAll(reason: "Stopped in the background.")
        let summary = try await task.value

        XCTAssertEqual(summary.failed, [LibraryImportFailure(fileName: "Big.gba", reason: "Stopped in the background.")])
        XCTAssertTrue(summary.cancelled.isEmpty)
        XCTAssertTrue(store.games.isEmpty)
        XCTAssertFalse(store.imports.isRunning)
        XCTAssertEqual(store.imports.items.map(\.state), [.failed("Stopped in the background.")])
        XCTAssertEqual(try gamesFolderContents(store), [], "a partial copy is left in Games/")

        // The next import starts a new round: the stopped one is no longer listed.
        LibraryStore.testChunkPause = 0
        let again = try await store.importInBackground(from: [inboxFile("Small.gba")])
        XCTAssertEqual(again.added.map(\.relativePath), ["Small.gba"])
        XCTAssertEqual(store.imports.items.map(\.name), ["Small.gba"])
        XCTAssertEqual(store.imports.items.map(\.state), [.done])
    }
    /// A copy whose source never answers (a pipe nothing writes, as a share that stopped
    /// responding) still stops on cancel, and leaves nothing behind.
    func testStalledCopyCancels() async throws {
        let store = LibraryStore(fileManager: fm, documentsDirectoryURL: root)
        let stalled = root.appendingPathComponent("Stalled.gba")
        XCTAssertEqual(mkfifo(stalled.path, 0o644), 0)
        let task = Task { try await store.importInBackground(from: [stalled]) }
        for _ in 0..<50 where store.imports.items.isEmpty {
            try await Task.sleep(for: .milliseconds(20))
        }
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertTrue(store.imports.isRunning)

        let start = Date()
        store.imports.cancel(try XCTUnwrap(store.imports.items.first).id)
        let summary = try await task.value

        XCTAssertLessThan(Date().timeIntervalSince(start), 7, "the stalled copy held the cancel")
        XCTAssertEqual(summary.cancelled, ["Stalled.gba"])
        XCTAssertTrue(store.games.isEmpty)
        XCTAssertEqual(try gamesFolderContents(store), [], "a partial copy is left in Games/")
        // Let the stuck read end.
        let writer = FileHandle(forWritingAtPath: stalled.path)
        try writer?.close()
    }
}
