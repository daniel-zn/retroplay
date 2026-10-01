// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
@testable import RetroPlayCore

final class RecentSearchesTests: XCTestCase {
    func testNewestFirstAndRepeatsMoveToFront() {
        var list: [String] = []
        list = RecentSearches.adding("zelda", to: list)
        list = RecentSearches.adding("crush", to: list)
        list = RecentSearches.adding("zelda", to: list)
        XCTAssertEqual(list, ["zelda", "crush"])
    }

    func testVariantsOfOneQueryAreOneEntry() {
        var list = RecentSearches.adding("Pokemon", to: [])
        list = RecentSearches.adding("  pokémon ", to: list)
        XCTAssertEqual(list, ["pokémon"])
    }

    func testBlankQueriesAreIgnored() {
        XCTAssertEqual(RecentSearches.adding("   ", to: ["crush"]), ["crush"])
        XCTAssertEqual(RecentSearches.adding(" - ", to: ["crush"]), ["crush"])
    }

    func testKeepsOnlyTheLimit() {
        var list: [String] = []
        for i in 0..<(RecentSearches.limit + 5) { list = RecentSearches.adding("game \(i)", to: list) }
        XCTAssertEqual(list.count, RecentSearches.limit)
        XCTAssertEqual(list.first, "game \(RecentSearches.limit + 4)")
    }

    func testRoundTripAndBadStoredValue() {
        let list = ["zelda", "crush"]
        XCTAssertEqual(RecentSearches.decode(RecentSearches.encode(list)), list)
        XCTAssertEqual(RecentSearches.decode(""), [])
        XCTAssertEqual(RecentSearches.decode("not json"), [])
    }
}
