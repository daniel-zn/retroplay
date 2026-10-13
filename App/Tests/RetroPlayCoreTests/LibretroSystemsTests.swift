// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
@testable import RetroPlayCore

/// NES, SNES, Genesis, Atari 7800 and PS1: routing files to the right system (shared
/// extensions are decided by contents), PS1 .cue sheets and their tracks, and controller roles.
final class LibretroSystemsTests: XCTestCase {
    private let fm = FileManager.default
    private lazy var root: URL = {
        let url = fm.temporaryDirectory.appendingPathComponent("rp-libretro-\(UUID().uuidString)", isDirectory: true)
        try? fm.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }()

    private func file(_ name: String, _ bytes: [UInt8]) throws -> URL {
        let url = root.appendingPathComponent(name)
        try Data(bytes).write(to: url)
        return url
    }

    /// `count` zero bytes with `patch` written at `offset`.
    private func bytes(_ count: Int, at offset: Int = 0, _ patch: [UInt8]) -> [UInt8] {
        var data = [UInt8](repeating: 0, count: count)
        data.replaceSubrange(offset ..< offset + patch.count, with: patch)
        return data
    }

    private let cdSync: [UInt8] = [0x00] + [UInt8](repeating: 0xFF, count: 10) + [0x00]

    // MARK: - Extensions

    func testUnambiguousExtensionsMapToTheirSystem() {
        XCTAssertEqual(SystemRegistry.system(forFileExtension: "nes"), .nes)
        XCTAssertEqual(SystemRegistry.system(forFileExtension: "SFC"), .snes)
        XCTAssertEqual(SystemRegistry.system(forFileExtension: "smc"), .snes)
        XCTAssertEqual(SystemRegistry.system(forFileExtension: "md"), .genesis)
        XCTAssertEqual(SystemRegistry.system(forFileExtension: "gen"), .genesis)
        XCTAssertEqual(SystemRegistry.system(forFileExtension: "a78"), .atari7800)
        XCTAssertEqual(SystemRegistry.system(forFileExtension: "cue"), .ps1)
        for ext in ["nes", "sfc", "md", "a78", "cue", "bin"] {
            XCTAssertTrue(ImportContentTypes.isSupportedExtension(ext), ext)
        }
    }

    func testEveryLibretroSystemNamesItsCore() {
        let libretro = SystemID.allCases.filter { $0.libretroCore != nil }
        XCTAssertEqual(Set(libretro), [.nes, .snes, .genesis, .atari7800, .ps1])
        XCTAssertEqual(SystemID.ps1.libretroCore, "pcsx_rearmed")
        XCTAssertEqual(SystemID.genesis.libretroCore, "clownmdemu")
        XCTAssertNil(SystemID.psp.libretroCore)
    }

    // MARK: - Shared extensions

    func testBinIsGenesisWithASegaHeaderAndPS1WithCDSectors() throws {
        let genesis = try file("Sonic.bin", bytes(0x400, at: 0x100, Array("SEGA GENESIS    ".utf8)))
        let ps1 = try file("Track.bin", bytes(2352, cdSync))
        let other = try file("Unknown.bin", bytes(0x400, [1, 2, 3]))
        XCTAssertEqual(DiscSniffer.system(forFileAt: genesis, fileExtension: "bin"), .genesis)
        XCTAssertEqual(DiscSniffer.system(forFileAt: ps1, fileExtension: "bin"), .ps1)
        XCTAssertNil(DiscSniffer.system(forFileAt: other, fileExtension: "bin"))
    }

    func testISOIsDecidedByTheVolumeSystemIdentifier() throws {
        func iso(_ systemID: String) -> [UInt8] {
            var data = bytes(0x8800, at: 0x8001, Array("CD001".utf8))
            data.replaceSubrange(0x8008 ..< 0x8008 + systemID.utf8.count, with: Array(systemID.utf8))
            return data
        }
        let ps1 = try file("Game1.iso", iso("PLAYSTATION"))
        let psp = try file("Game2.iso", iso("PSP GAME"))
        let raw = try file("Game3.iso", bytes(2352, cdSync))
        XCTAssertEqual(DiscSniffer.system(forFileAt: ps1, fileExtension: "iso"), .ps1)
        XCTAssertEqual(DiscSniffer.system(forFileAt: psp, fileExtension: "iso"), .psp)
        XCTAssertEqual(DiscSniffer.system(forFileAt: raw, fileExtension: "iso"), .ps1)
    }

    func testPBPIsPS1WhenItsPSARHoldsADiscImage() throws {
        func pbp(_ psar: String) -> [UInt8] {
            var data = bytes(0x200, [0x00, 0x50, 0x42, 0x50])
            data.replaceSubrange(36 ..< 40, with: [0x00, 0x01, 0x00, 0x00]) // DATA.PSAR at 0x100
            data.replaceSubrange(0x100 ..< 0x100 + psar.utf8.count, with: Array(psar.utf8))
            return data
        }
        let ps1 = try file("Game1.pbp", pbp("PSISOIMG0000"))
        let psp = try file("Game2.pbp", pbp("NPUMDIMG"))
        XCTAssertEqual(DiscSniffer.system(forFileAt: ps1, fileExtension: "pbp"), .ps1)
        XCTAssertEqual(DiscSniffer.system(forFileAt: psp, fileExtension: "pbp"), .psp)
    }

    func testCHDIsPS1ForCDMetadataAndPSPForDVD() throws {
        func chd(_ tag: String) -> [UInt8] {
            var data = bytes(0x200, Array("MComprHD".utf8))
            data.replaceSubrange(12 ..< 16, with: [0, 0, 0, 5]) // version 5
            data.replaceSubrange(48 ..< 56, with: [0, 0, 0, 0, 0, 0, 0x01, 0x00]) // metadata at 0x100
            data.replaceSubrange(0x100 ..< 0x104, with: Array(tag.utf8))
            return data
        }
        let cd = try file("Game1.chd", chd("CHT2"))
        let dvd = try file("Game2.chd", chd("DVD "))
        XCTAssertEqual(DiscSniffer.system(forFileAt: cd, fileExtension: "chd"), .ps1)
        XCTAssertEqual(DiscSniffer.system(forFileAt: dvd, fileExtension: "chd"), .psp)
    }

    func testExeIsPS1OnlyWithAPSXHeader() throws {
        let psx = try file("Demo.exe", Array("PS-X EXE".utf8) + [UInt8](repeating: 0, count: 0x800))
        let windows = try file("Setup.exe", Array("MZ".utf8) + [UInt8](repeating: 0, count: 0x800))
        XCTAssertEqual(DiscSniffer.system(forFileAt: psx, fileExtension: "exe"), .ps1)
        XCTAssertNil(DiscSniffer.system(forFileAt: windows, fileExtension: "exe"))
    }

    func testImporterRefusesABinThatIsNeitherSystem() throws {
        let other = try file("Mystery.bin", bytes(0x400, [9]))
        XCTAssertThrowsError(try ROMImporter().makeLibraryEntry(
            originalFileName: "Mystery.bin",
            sandboxRelativePath: "Mystery.bin",
            fileExtension: "bin",
            sandboxFileURL: other
        ))
        let ps1 = try file("Disc.bin", bytes(2352, cdSync))
        let entry = try ROMImporter().makeLibraryEntry(
            originalFileName: "Disc.bin",
            sandboxRelativePath: "Disc.bin",
            fileExtension: "bin",
            sandboxFileURL: ps1
        )
        XCTAssertEqual(entry.systemID, .ps1)
    }

    // MARK: - Cue sheets

    func testCueSheetListsItsTrackFiles() {
        let sheet = """
        FILE "Game (Track 1).bin" BINARY
          TRACK 01 MODE2/2352
            INDEX 01 00:00:00
        FILE "Game (Track 2).bin" BINARY
          TRACK 02 AUDIO
        file Unquoted.bin BINARY
        FILE "C:\\\\Games\\\\Windows.bin" BINARY
        FILE "../escape.bin" BINARY
        FILE "Game (Track 1).bin" BINARY
        """
        XCTAssertEqual(CueSheet.referencedFiles(in: sheet), [
            "Game (Track 1).bin", "Game (Track 2).bin", "Unquoted.bin", "Windows.bin", "escape.bin",
        ])
    }

    @MainActor
    func testCueAndTracksImportIntoOneFolderAsOneGame() throws {
        let inbox = root.appendingPathComponent("inbox", isDirectory: true)
        try fm.createDirectory(at: inbox, withIntermediateDirectories: true)
        let cue = inbox.appendingPathComponent("Game.cue")
        try Data("FILE \"Game.bin\" BINARY\n  TRACK 01 MODE2/2352\n".utf8).write(to: cue)
        let bin = inbox.appendingPathComponent("Game.bin")
        try Data(cdSync + [UInt8](repeating: 7, count: 100)).write(to: bin)
        let documents = root.appendingPathComponent("docs", isDirectory: true)
        let store = LibraryStore(fileManager: fm, documentsDirectoryURL: documents)

        let summary = try store.importSummary(from: [bin, cue])

        XCTAssertEqual(summary.added.map(\.relativePath), ["Game/Game.cue"])
        XCTAssertEqual(summary.added.first?.systemID, .ps1)
        XCTAssertTrue(summary.failed.isEmpty)
        let folder = store.gamesDirectoryURL.appendingPathComponent("Game", isDirectory: true)
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: folder.path).sorted(), ["Game.bin", "Game.cue"])

        // Deleting the game removes the whole disc folder.
        let game = try XCTUnwrap(summary.added.first)
        try GameArtifactCleanup.removeArtifacts(for: game, paths: SavePaths(fileManager: fm, documentsURL: documents))
        XCTAssertFalse(fm.fileExists(atPath: folder.path))
    }

    @MainActor
    func testCueWithoutItsTracksFailsAndLeavesNothing() throws {
        let inbox = root.appendingPathComponent("inbox2", isDirectory: true)
        try fm.createDirectory(at: inbox, withIntermediateDirectories: true)
        let cue = inbox.appendingPathComponent("Lonely.cue")
        try Data("FILE \"Lonely.bin\" BINARY\n".utf8).write(to: cue)
        let documents = root.appendingPathComponent("docs2", isDirectory: true)
        let store = LibraryStore(fileManager: fm, documentsDirectoryURL: documents)

        let summary = try store.importSummary(from: [cue])

        XCTAssertTrue(summary.added.isEmpty)
        XCTAssertEqual(summary.failed.map(\.fileName), ["Lonely.cue"])
        XCTAssertTrue(try XCTUnwrap(summary.failed.first).reason.contains("Lonely.bin"))
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: store.gamesDirectoryURL.path), [])
    }

    // MARK: - Controllers

    func testPhysicalPadRolesFollowEachPadsLayout() {
        func buttons(_ roles: PadRole, _ system: SystemID) -> RetroPadInput {
            RetroPadInput(rawValue: ControllerMapping.map(PhysicalPadState(roles: roles), for: system).buttons)
        }
        XCTAssertEqual(buttons(.east, .nes), [RetroPadInput.NES.a])
        XCTAssertEqual(buttons(.south, .nes), [RetroPadInput.NES.b])
        XCTAssertEqual(buttons([.west, .south, .east], .genesis),
                       [RetroPadInput.Genesis.a, RetroPadInput.Genesis.b, RetroPadInput.Genesis.c])
        XCTAssertEqual(buttons([.south, .leftTrigger], .ps1), [RetroPadInput.PS1.cross, RetroPadInput.PS1.l2])
        XCTAssertEqual(buttons([.north, .start], .snes), [RetroPadInput.SNES.x, .start])
        let stick = ControllerMapping.map(PhysicalPadState(leftStickX: 1), for: .atari7800)
        XCTAssertEqual(RetroPadInput(rawValue: stick.buttons), [.right])
    }
}
