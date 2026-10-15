// SPDX-License-Identifier: GPL-3.0-or-later
import UIKit
import XCTest
@testable import RetroPlayCore

/// The player's own covers: a picture named like a game's file, picked in Import (with the game
/// or later) or dropped into Games/, becomes the game's cover and nothing replaces it.
@MainActor
final class CustomCoversTests: XCTestCase {
    private let fm = FileManager.default
    private lazy var root: URL = {
        let url = fm.temporaryDirectory.appendingPathComponent("rp-custom-covers-\(UUID().uuidString)", isDirectory: true)
        try? fm.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }()

    private func inbox(_ name: String, _ data: Data) throws -> URL {
        let dir = root.appendingPathComponent("inbox-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }

    private func jpeg() -> Data {
        UIGraphicsImageRenderer(size: CGSize(width: 60, height: 100)).jpegData(withCompressionQuality: 0.9) {
            UIColor.red.setFill(); $0.fill(CGRect(x: 0, y: 0, width: 60, height: 100))
        }
    }

    func testPictureNamedLikeTheGameBecomesItsCover() throws {
        let documents = root.appendingPathComponent("docs", isDirectory: true)
        let store = LibraryStore(fileManager: fm, documentsDirectoryURL: documents)
        let rom = try inbox("Crush ULUS10238.gba", Data("rom".utf8))
        let picture = try inbox("crush ulus10238.JPG", jpeg())
        let stray = try inbox("Something Else.png", jpeg())

        let summary = try store.importSummary(from: [rom, picture, stray])

        let game = try XCTUnwrap(summary.added.first)
        XCTAssertEqual(summary.covers, ["crush ulus10238.JPG"])
        XCTAssertEqual(summary.unsupported, ["Something Else.png"])
        let covers = CoverArtStore(fileManager: fm, documentsDirectoryURL: documents)
        XCTAssertEqual(covers.origin(forGameID: game.id), .custom)
        // Box art and art from the game file never replace it.
        XCTAssertFalse(try covers.installBoxArt(jpeg(), forGameID: game.id))
        XCTAssertEqual(covers.origin(forGameID: game.id), .custom)
        // The picture isn't a library row or a file in Games/.
        XCTAssertEqual(store.games.count, 1)
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: store.gamesDirectoryURL.path), ["Crush ULUS10238.gba"])
    }

    func testPicturePickedLaterAndPictureDroppedInGamesFolder() async throws {
        let documents = root.appendingPathComponent("docs2", isDirectory: true)
        let store = LibraryStore(fileManager: fm, documentsDirectoryURL: documents)
        let game = try XCTUnwrap(try store.importSummary(from: [try inbox("Daxter.gba", Data("rom".utf8))]).added.first)
        let covers = CoverArtStore(fileManager: fm, documentsDirectoryURL: documents)
        XCTAssertNil(covers.origin(forGameID: game.id))

        let later = try store.importSummary(from: [try inbox("Daxter.png", jpeg())])
        XCTAssertEqual(later.covers, ["Daxter.png"])
        XCTAssertEqual(covers.origin(forGameID: game.id), .custom)

        // A newer picture dropped into Games/ (Files → RetroPlay → Games) replaces it.
        let before = store.coversRevision
        let dropped = store.gamesDirectoryURL.appendingPathComponent("Daxter.jpg")
        try jpeg().write(to: dropped)
        try fm.setAttributes([.modificationDate: Date().addingTimeInterval(60)], ofItemAtPath: dropped.path)
        await store.reconcileWithGamesFolder()
        XCTAssertEqual(store.coversRevision, before + 1)
        XCTAssertEqual(store.games.count, 1)
        // Unchanged since: not applied again.
        await store.reconcileWithGamesFolder()
        XCTAssertEqual(store.coversRevision, before + 1)
    }
}
