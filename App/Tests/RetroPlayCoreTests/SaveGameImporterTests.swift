// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
@testable import RetroPlayCore

final class SaveGameImporterTests: XCTestCase {
    private func tempRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("rp-save-import-\(UUID().uuidString)", isDirectory: true)
    }

    private func sampleGame(system: SystemID, name: String) -> LibraryGame {
        let ext: String
        switch system {
        case .gba: ext = "gba"
        case .n64: ext = "z64"
        case .nds: ext = "nds"
        case .psp: ext = "iso"
        case .nes: ext = "nes"
        case .snes: ext = "sfc"
        case .genesis: ext = "md"
        case .atari7800: ext = "a78"
        case .ps1: ext = "cue"
        }
        return LibraryGame(
            displayName: name,
            systemID: system,
            relativePath: "\(name).\(ext)"
        )
    }

    func testRejectsSaveStateExtension() throws {
        let fm = FileManager.default
        let root = tempRoot()
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let state = root.appendingPathComponent("Pokemon.slot0.state")
        try Data([0x01]).write(to: state)
        let importer = SaveGameImporter()
        let game = sampleGame(system: .gba, name: "Pokemon")

        XCTAssertThrowsError(try importer.planImport(from: state, for: game, paths: SavePaths(documentsURL: root))) { error in
            XCTAssertEqual(error as? SaveGameImportError, .saveStateNotImportable)
        }
    }

    func testGBAImportRenamesMatchingSRMToSAVDestination() throws {
        let fm = FileManager.default
        let root = tempRoot()
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let paths = SavePaths(fileManager: fm, documentsURL: root)
        try paths.ensureDirectories(fileManager: fm)

        let source = root.appendingPathComponent("Zelda.srm")
        try Data(count: 32_768).write(to: source)

        let game = sampleGame(system: .gba, name: "Zelda")
        let importer = SaveGameImporter()
        let plan = try importer.planImport(from: source, for: game, paths: paths, fileManager: fm)

        XCTAssertTrue(plan.destinationURL.path.hasSuffix("/Saves/Zelda.sav"))
        XCTAssertFalse(plan.replacesExisting)
        try importer.commitImport(plan: plan, from: source, overwrite: false, fileManager: fm)
        XCTAssertTrue(fm.fileExists(atPath: plan.destinationURL.path))
    }

    func testN64Requires290KiBSRM() throws {
        let fm = FileManager.default
        let root = tempRoot()
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let paths = SavePaths(fileManager: fm, documentsURL: root)
        try paths.ensureDirectories(fileManager: fm)

        let bad = root.appendingPathComponent("Mario.srm")
        try Data(count: 512).write(to: bad)
        let game = sampleGame(system: .n64, name: "Mario")
        let importer = SaveGameImporter()

        XCTAssertThrowsError(try importer.planImport(from: bad, for: game, paths: paths, fileManager: fm)) { error in
            guard case .invalidSize(let system, let bytes) = error as? SaveGameImportError else {
                return XCTFail("expected invalidSize, got \(error)")
            }
            XCTAssertEqual(system, .n64)
            XCTAssertEqual(bytes, 512)
        }
    }

    func testPSPSavedataFolderRequiresPARAMSFO() throws {
        let fm = FileManager.default
        let root = tempRoot()
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let paths = SavePaths(fileManager: fm, documentsURL: root)
        try paths.ensureDirectories(fileManager: fm)

        let folder = root.appendingPathComponent("ULUS12345", isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("SAVE".utf8).write(to: folder.appendingPathComponent("SAVE.BIN"))

        let importer = SaveGameImporter()
        let game = sampleGame(system: .psp, name: "Game")

        XCTAssertThrowsError(try importer.planImport(from: folder, for: game, paths: paths, fileManager: fm)) { error in
            XCTAssertEqual(error as? SaveGameImportError, .missingPSPMetadata)
        }
    }

    func testPSPSavedataFolderCopiesIntoMemstickTree() throws {
        let fm = FileManager.default
        let root = tempRoot()
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let paths = SavePaths(fileManager: fm, documentsURL: root)
        try paths.ensureDirectories(fileManager: fm)

        let folder = root.appendingPathComponent("ULUS12345", isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("SFO".utf8).write(to: folder.appendingPathComponent("PARAM.SFO"))
        try Data("BIN".utf8).write(to: folder.appendingPathComponent("SAVE.BIN"))

        let importer = SaveGameImporter()
        let game = sampleGame(system: .psp, name: "Game")
        let plan = try importer.planImport(from: folder, for: game, paths: paths, fileManager: fm)

        XCTAssertTrue(plan.destinationURL.path.hasSuffix("/Saves/psp-memstick/PSP/SAVEDATA/ULUS12345"))
        try importer.commitImport(plan: plan, from: folder, overwrite: false, fileManager: fm)
        XCTAssertTrue(fm.fileExists(atPath: plan.destinationURL.appendingPathComponent("PARAM.SFO").path))
    }

    func testFailedOverwritePreservesExistingSave() throws {
        let fm = FileManager.default
        let root = tempRoot()
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let paths = SavePaths(fileManager: fm, documentsURL: root)
        try paths.ensureDirectories(fileManager: fm)

        let dest = paths.sramURL(forRelativeROMPath: "Zelda.gba")
        let original = Data([0xAA, 0xBB, 0xCC])
        try original.write(to: dest)

        let source = root.appendingPathComponent("Zelda.sav")
        try Data(count: 32_768).write(to: source)

        let importer = SaveGameImporter()
        let game = sampleGame(system: .gba, name: "Zelda")
        let plan = try importer.planImport(from: source, for: game, paths: paths, fileManager: fm)

        let failingSource = root.appendingPathComponent("missing-\(UUID().uuidString).sav")
        XCTAssertThrowsError(
            try importer.commitImport(plan: plan, from: failingSource, overwrite: true, fileManager: fm)
        )

        XCTAssertEqual(try Data(contentsOf: dest), original)
    }

    func testOverwriteRequiresExplicitConfirmation() throws {
        let fm = FileManager.default
        let root = tempRoot()
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let paths = SavePaths(fileManager: fm, documentsURL: root)
        try paths.ensureDirectories(fileManager: fm)

        let dest = paths.sramURL(forRelativeROMPath: "Zelda.gba")
        try Data([0xAA]).write(to: dest)

        let source = root.appendingPathComponent("Zelda.sav")
        try Data(count: 32_768).write(to: source)

        let importer = SaveGameImporter()
        let game = sampleGame(system: .gba, name: "Zelda")
        let plan = try importer.planImport(from: source, for: game, paths: paths, fileManager: fm)
        XCTAssertTrue(plan.replacesExisting)

        XCTAssertThrowsError(
            try importer.commitImport(plan: plan, from: source, overwrite: false, fileManager: fm)
        ) { error in
            guard case .destinationExists = error as? SaveGameImportError else {
                return XCTFail("expected destinationExists")
            }
        }
    }

    func testSaveStateExtensionDoesNotRejectUnrelatedBatteryExtensions() {
        XCTAssertTrue(SaveImportContentTypes.isSaveStateExtension("state"))
        XCTAssertFalse(SaveImportContentTypes.isSaveStateExtension("srm"))
        XCTAssertFalse(SaveImportContentTypes.isSaveStateExtension("stats"))
    }

    func testDetectsRzipCompressedRetroArchSave() {
        let header = Data("#RZIP".utf8)
        XCTAssertTrue(SaveGameImporter.looksRzipCompressed(header))
    }

    func testNestedGBAImportUsesRelativeDestination() throws {
        let fm = FileManager.default
        let root = tempRoot()
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let paths = SavePaths(fileManager: fm, documentsURL: root)
        try paths.ensureDirectories(fileManager: fm)

        let source = root.appendingPathComponent("Zelda.sav")
        try Data(count: 32_768).write(to: source)

        let game = LibraryGame(
            displayName: "Zelda",
            systemID: .gba,
            relativePath: "Pocket/Zelda.gba"
        )
        let importer = SaveGameImporter()
        let plan = try importer.planImport(from: source, for: game, paths: paths, fileManager: fm)

        XCTAssertTrue(plan.destinationURL.path.hasSuffix("/Saves/Pocket/Zelda.sav"))
    }

    func testRejectsSavedataFolderForNonPSPGame() throws {
        let fm = FileManager.default
        let root = tempRoot()
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let paths = SavePaths(fileManager: fm, documentsURL: root)
        try paths.ensureDirectories(fileManager: fm)

        let folder = root.appendingPathComponent("ULUS12345", isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("SFO".utf8).write(to: folder.appendingPathComponent("PARAM.SFO"))

        let importer = SaveGameImporter()
        let game = sampleGame(system: .gba, name: "Zelda")

        XCTAssertThrowsError(try importer.planImport(from: folder, for: game, paths: paths, fileManager: fm)) { error in
            guard case .unsupportedFormat(let detail) = error as? SaveGameImportError else {
                return XCTFail("expected unsupportedFormat, got \(error)")
            }
            XCTAssertTrue(detail.contains("PSP SAVEDATA"))
        }
    }

    func testBasenameMismatchIsExplicit() throws {
        let fm = FileManager.default
        let root = tempRoot()
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let paths = SavePaths(fileManager: fm, documentsURL: root)
        try paths.ensureDirectories(fileManager: fm)

        let source = root.appendingPathComponent("WrongName.sav")
        try Data(count: 32_768).write(to: source)
        let game = sampleGame(system: .gba, name: "Zelda")
        let importer = SaveGameImporter()

        XCTAssertThrowsError(try importer.planImport(from: source, for: game, paths: paths, fileManager: fm)) { error in
            XCTAssertEqual(error as? SaveGameImportError, .basenameMismatch(expected: "Zelda", got: "WrongName"))
        }
    }

    func testRejectsSavedataRootDirectory() throws {
        let fm = FileManager.default
        let root = tempRoot()
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let paths = SavePaths(fileManager: fm, documentsURL: root)
        try paths.ensureDirectories(fileManager: fm)

        let folder = root.appendingPathComponent("SAVEDATA", isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)

        let importer = SaveGameImporter()
        let game = sampleGame(system: .psp, name: "Game")

        XCTAssertThrowsError(try importer.planImport(from: folder, for: game, paths: paths, fileManager: fm)) { error in
            guard case .unsupportedFormat(let detail) = error as? SaveGameImportError else {
                return XCTFail("expected unsupportedFormat, got \(error)")
            }
            XCTAssertTrue(detail.contains("SAVEDATA"))
        }
    }

    func testPSPImportRejectsUnsafeSavedataFolderNames() {
        XCTAssertFalse(SavePaths.isSafeFileName("../ULUS12345"))
        XCTAssertFalse(SavePaths.isSafeFileName("ULUS/12345"))
        XCTAssertFalse(SavePaths.isSafeFileName(""))
        XCTAssertTrue(SavePaths.isSafeFileName("ULUS12345"))
    }

    func testPSPSavedataOverwritePreservesExistingFolderOnMoveFailure() throws {
        let fm = FileManager.default
        let root = tempRoot()
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let paths = SavePaths(fileManager: fm, documentsURL: root)
        try paths.ensureDirectories(fileManager: fm)

        let existing = paths.pspSavedataDirectory.appendingPathComponent("ULUS12345", isDirectory: true)
        try fm.createDirectory(at: existing, withIntermediateDirectories: true)
        try Data("ORIGINAL".utf8).write(to: existing.appendingPathComponent("PARAM.SFO"))
        try Data("OLD".utf8).write(to: existing.appendingPathComponent("SAVE.BIN"))

        let source = root.appendingPathComponent("ULUS12345", isDirectory: true)
        try fm.createDirectory(at: source, withIntermediateDirectories: true)
        try Data("NEW-SFO".utf8).write(to: source.appendingPathComponent("PARAM.SFO"))
        try Data("NEW".utf8).write(to: source.appendingPathComponent("SAVE.BIN"))

        let importer = SaveGameImporter()
        let game = sampleGame(system: .psp, name: "Game")
        let plan = try importer.planImport(from: source, for: game, paths: paths, fileManager: fm)
        try importer.commitImport(plan: plan, from: source, overwrite: true, fileManager: fm)

        XCTAssertEqual(try Data(contentsOf: existing.appendingPathComponent("SAVE.BIN")), Data("NEW".utf8))
        XCTAssertEqual(try Data(contentsOf: existing.appendingPathComponent("PARAM.SFO")), Data("NEW-SFO".utf8))
    }

    func testCommitImportOverwritesExistingBatterySave() throws {
        let fm = FileManager.default
        let root = tempRoot()
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let paths = SavePaths(fileManager: fm, documentsURL: root)
        try paths.ensureDirectories(fileManager: fm)

        let source = root.appendingPathComponent("Zelda.sav")
        try Data(repeating: 0xAB, count: 32_768).write(to: source)

        let game = sampleGame(system: .gba, name: "Zelda")
        let importer = SaveGameImporter()
        let plan = try importer.planImport(from: source, for: game, paths: paths, fileManager: fm)
        try Data(repeating: 0x01, count: 32_768).write(to: plan.destinationURL)

        try importer.commitImport(plan: plan, from: source, overwrite: true, fileManager: fm)
        let imported = try Data(contentsOf: plan.destinationURL)
        XCTAssertEqual(imported, Data(repeating: 0xAB, count: 32_768))
    }
}
