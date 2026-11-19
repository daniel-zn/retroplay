// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
@testable import RetroPlayCore

@MainActor
final class LibraryStoreMissingTests: XCTestCase {
    /// A tap checks only the tapped game's file: the others keep what the last full check found.
    func testCheckingOneGameLeavesTheOthersAlone() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("rp-missing-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let store = LibraryStore(fileManager: fm, documentsDirectoryURL: root)
        var inboxes: [URL] = []
        for name in ["one.gba", "two.gba"] {
            let url = root.appendingPathComponent(name)
            try Data("not-a-copyrighted-rom-\(name)".utf8).write(to: url)
            inboxes.append(url)
        }
        let added = try store.importFiles(from: inboxes)
        XCTAssertEqual(added.count, 2)
        let tapped = added[0], other = added[1]

        try fm.removeItem(at: store.absoluteURL(for: tapped))
        try fm.removeItem(at: store.absoluteURL(for: other))

        XCTAssertTrue(store.refreshMissing(tapped))
        XCTAssertEqual(store.missingGameIDs, [tapped.id])

        try Data("back".utf8).write(to: store.absoluteURL(for: tapped))
        XCTAssertFalse(store.refreshMissing(tapped))
        XCTAssertEqual(store.missingGameIDs, [])
    }
}
