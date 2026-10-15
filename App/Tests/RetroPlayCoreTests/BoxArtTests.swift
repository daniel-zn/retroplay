// SPDX-License-Identifier: GPL-3.0-or-later
import UIKit
import XCTest
@testable import RetroPlayCore

/// Box art lookup: parsing the server's folder index, matching a library game to a release
/// name (exact titles only, the right region, no betas or re-releases), and storing covers.
final class BoxArtTests: XCTestCase {
    func testIndexParsingKeepsOnlyPNGReleaseNames() {
        let html = """
        <a href="?C=N;O=D">Name</a> <a href="../">Parent</a>
        <a href="Legend%20of%20Zelda%2C%20The%20-%20Ocarina%20of%20Time%20(USA).png">x</a>
        <a href="Super%20Mario%20Bros.%203%20(USA)%20(Rev%201).png">x</a>
        <a href="notes.txt">x</a>
        """
        XCTAssertEqual(BoxArt.parseIndex(html), [
            "Legend of Zelda, The - Ocarina of Time (USA)",
            "Super Mario Bros. 3 (USA) (Rev 1)",
        ])
    }

    func testTitlesCompareWithoutTagsArticlesPunctuationOrExtension() {
        XCTAssertEqual(
            BoxArt.normalizedTitle("The Legend of Zelda - Ocarina of Time"),
            BoxArt.normalizedTitle("Legend of Zelda, The - Ocarina of Time (USA) (Rev 1)")
        )
        XCTAssertEqual(
            BoxArt.normalizedTitle("Legend of Zelda, The - Ocarina of Time.z64"),
            "legend of zelda ocarina of time"
        )
        XCTAssertEqual(BoxArt.normalizedTitle("Super Mario Bros. 3"), "super mario bros 3")
        XCTAssertEqual(BoxArt.normalizedTitle("Ratchet & Clank"), BoxArt.normalizedTitle("Ratchet and Clank (USA)"))
    }

    private let zelda = [
        "Legend of Zelda, The - Ocarina of Time (Europe) (Beta) (2003-02-13) (GameCube)",
        "Legend of Zelda, The - Ocarina of Time (Europe) (En,Fr,De) (Rev 1)",
        "Legend of Zelda, The - Ocarina of Time (Japan)",
        "Legend of Zelda, The - Ocarina of Time (USA) (Rev 1)",
        "Legend of Zelda, The - Ocarina of Time (USA)",
        "Legend of Zelda, The - Ocarina of Time - Master Quest (USA) (GameCube)",
    ]

    func testPrefersTheUSReleaseAndSkipsBetasAndOtherGames() {
        XCTAssertEqual(
            BoxArt.bestMatch(
                title: "The Legend of Zelda - Ocarina of Time",
                fileName: "Legend of Zelda, The - Ocarina of Time.z64",
                in: zelda
            ),
            "Legend of Zelda, The - Ocarina of Time (USA)"
        )
    }

    func testFollowsTheRegionInTheFileName() {
        XCTAssertEqual(
            BoxArt.bestMatch(
                title: "The Legend of Zelda - Ocarina of Time",
                fileName: "Legend of Zelda, The - Ocarina of Time (Japan).z64",
                in: zelda
            ),
            "Legend of Zelda, The - Ocarina of Time (Japan)"
        )
    }

    func testNoCoverRatherThanAnotherGames() {
        // "Toy Story 3" must not pick "Toy Story 2", nor a title that merely starts the same.
        let names = ["Toy Story 2 (USA)", "Toy Story 3 - The Video Game (USA)", "Crush Pinball (USA)"]
        XCTAssertNil(BoxArt.bestMatch(title: "Toy Story 3", fileName: "Toy Story 3.nds", in: names))
        XCTAssertNil(BoxArt.bestMatch(title: "Crush", fileName: "Crush ULUS10238.iso", in: names))
    }

    func testEveryServerFolderNameIsSet() {
        for system in SystemID.allCases {
            XCTAssertTrue(BoxArt.indexURL(for: system).absoluteString.hasPrefix("https://thumbnails.libretro.com/"))
            XCTAssertTrue(BoxArt.indexURL(for: system).absoluteString.hasSuffix("/Named_Boxarts/"))
        }
        XCTAssertEqual(
            BoxArt.imageURL(for: .n64, name: "Legend of Zelda, The - Ocarina of Time (USA)").absoluteString,
            "https://thumbnails.libretro.com/Nintendo%20-%20Nintendo%2064/Named_Boxarts/"
                + "Legend%20of%20Zelda,%20The%20-%20Ocarina%20of%20Time%20(USA).png"
        )
    }

    func testBoxArtIsStoredAndNotReplacedByArtFromTheGameFile() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("rp-boxart-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = CoverArtStore(documentsDirectoryURL: root)
        let id = UUID()
        XCTAssertTrue(try store.installBoxArt(Self.png(width: 1200, height: 1200), forGameID: id))
        XCTAssertEqual(store.origin(forGameID: id), .boxArt)
        let stored = try XCTUnwrap(UIImage(contentsOfFile: store.coverURL(forGameID: id).path))
        XCTAssertLessThanOrEqual(max(stored.size.width, stored.size.height) * stored.scale, 600)

        // A PSP file with an ICON0 would normally install its icon; box art wins.
        let psp = root.appendingPathComponent("Game.iso")
        try Data(count: 4096).write(to: psp)
        XCTAssertFalse(try store.installFromGameFile(gameID: id, fileURL: psp, system: .psp))
        XCTAssertEqual(store.origin(forGameID: id), .boxArt)
    }

    func testLookupsAreRemembered() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("rp-boxart-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = BoxArtIndexCache(paths: SavePaths(documentsURL: root))
        XCTAssertNil(cache.names(for: .gba))
        cache.store(["A (USA)"], for: .gba)
        XCTAssertEqual(cache.names(for: .gba), ["A (USA)"])
        XCTAssertNil(cache.names(for: .gba, now: Date().addingTimeInterval(BoxArtIndexCache.maxAge + 60)))
        let id = UUID()
        cache.markLookedUp([id])
        XCTAssertNotNil(cache.lookedUp()[id])
        cache.forgetLookups()
        XCTAssertTrue(cache.lookedUp().isEmpty)
    }

    private static func png(width: Int, height: Int) -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height),
                                               format: { let f = UIGraphicsImageRendererFormat(); f.scale = 1; return f }())
        return renderer.pngData { context in
            UIColor.orange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }
}
