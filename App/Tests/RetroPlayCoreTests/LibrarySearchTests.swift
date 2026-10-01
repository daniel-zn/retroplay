// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
@testable import RetroPlayCore

final class LibrarySearchTests: XCTestCase {
    private func game(_ name: String, _ system: SystemID = .gba) -> LibraryGame {
        LibraryGame(displayName: name, systemID: system, relativePath: "\(name).bin")
    }

    private let names: (SystemID) -> [String] = { [$0.displayName, "PSP", $0.defaultCoreName] }

    func testIgnoresAccentsAndCase() {
        XCTAssertTrue(LibrarySearch.matches(game("Pokémon Emerald"), query: "pokemon"))
        XCTAssertTrue(LibrarySearch.matches(game("Pokemon Emerald"), query: "POKÉMON"))
    }

    func testWordsNeedNotBeAdjacentAndPunctuationIsIgnored() {
        let zelda = game("The Legend of Zelda - The Minish Cap")
        XCTAssertTrue(LibrarySearch.matches(zelda, query: "zelda minish"))
        XCTAssertTrue(LibrarySearch.matches(zelda, query: "Zelda: Minish"))
        XCTAssertTrue(LibrarySearch.matches(zelda, query: "legend   cap"))
        XCTAssertFalse(LibrarySearch.matches(zelda, query: "zelda ocarina"))
    }

    func testSystemNameListsOnlyOnExactMatch() {
        let crush = game("Crush", .psp)
        XCTAssertTrue(LibrarySearch.matches(crush, query: "psp", systemNames: names))
        XCTAssertTrue(LibrarySearch.matches(crush, query: "PlayStation Portable", systemNames: names))
        // A fragment of a system name no longer lists every game of that system.
        XCTAssertFalse(LibrarySearch.matches(crush, query: "po", systemNames: names))
        XCTAssertFalse(LibrarySearch.matches(crush, query: "station", systemNames: names))
    }

    func testBlankQueryMatchesNothing() {
        XCTAssertFalse(LibrarySearch.matches(game("Crush"), query: "   "))
        XCTAssertFalse(LibrarySearch.matches(game("Crush"), query: " - "))
    }
}
