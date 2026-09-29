// SPDX-License-Identifier: GPL-3.0-or-later
import CryptoKit
import XCTest
@testable import RetroPlayCore

final class PSPSaveFlowTests: XCTestCase {
    func testMemstickSavedataIsNotTheQuickStateFolder() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("rp-psp-save-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let paths = SavePaths(fileManager: fm, documentsURL: root)
        try paths.ensureDirectories(fileManager: fm)

        XCTAssertTrue(paths.pspSavedataDirectory.path.hasSuffix("/Saves/psp-memstick/PSP/SAVEDATA"))
        XCTAssertTrue(fm.fileExists(atPath: paths.pspSavedataDirectory.path))
        XCTAssertTrue(fm.fileExists(atPath: paths.pspGameDirectory.path))
        XCTAssertTrue(fm.fileExists(atPath: paths.pspSystemDirectory.path))

        let gameID = UUID()
        let quick = try SaveStateStore.quickSaveURL(system: .psp, gameID: gameID, paths: paths)
        XCTAssertTrue(quick.path.contains("/States/psp/"))
        XCTAssertFalse(quick.path.contains("/SAVEDATA/"))
        XCTAssertFalse(quick.path.hasPrefix(paths.pspSavedataDirectory.path))
    }



    func testHostConfigAppliesCrossPreferenceBeforeBoot() {
        XCTAssertEqual(PPSSPPHostConfig.buttonPreferenceCross, PPSSPPDefaults.buttonPreferenceCross)
        XCTAssertTrue(PPSSPPHostConfig.savedataDialogUsesCrossAsOK(buttonPreference: PPSSPPHostConfig.buttonPreferenceCross))
        XCTAssertFalse(PPSSPPHostConfig.savedataDialogUsesCrossAsOK(buttonPreference: 0))
    }

    func testMemstickTreeIsReadyAfterEnsureDirectories() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("rp-psp-host-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let paths = SavePaths(fileManager: fm, documentsURL: root)
        try paths.ensureDirectories(fileManager: fm)

        XCTAssertTrue(PPSSPPHostConfig.memstickLooksReady(at: paths.pspMemstickDirectory, fileManager: fm))
        XCTAssertTrue(fm.fileExists(atPath: paths.pspSavedataDirectory.path))
    }


    func testEnsureMemstickDefaultsWritesCrossPreferenceIni() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("rp-psp-ini-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        try PPSSPPHostConfig.ensureMemstickDefaults(at: root, fileManager: fm)

        let iniURL = root.appendingPathComponent("ppsspp.ini")
        XCTAssertTrue(fm.fileExists(atPath: iniURL.path))
        let contents = try String(contentsOf: iniURL, encoding: .utf8)
        XCTAssertTrue(contents.contains("ButtonPreference = \(PPSSPPHostConfig.buttonPreferenceCross)"))
        XCTAssertTrue(contents.contains("CPUCore = \(PPSSPPDefaults.appStoreCPUCore.rawValue)"))
        XCTAssertTrue(PPSSPPHostConfig.memstickLooksReady(at: root, fileManager: fm))
    }

    func testMemstickDefaultsAreIdempotent() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("rp-psp-ini2-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        try PPSSPPHostConfig.ensureMemstickDefaults(at: root, fileManager: fm)
        let first = try String(contentsOf: root.appendingPathComponent("ppsspp.ini"), encoding: .utf8)
        try PPSSPPHostConfig.ensureMemstickDefaults(at: root, fileManager: fm)
        let second = try String(contentsOf: root.appendingPathComponent("ppsspp.ini"), encoding: .utf8)
        XCTAssertEqual(first, second)
    }

    func testMemstickIniRewritesStaleJITCPUCore() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("rp-psp-ini-jit-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let iniURL = root.appendingPathComponent("ppsspp.ini")
        try """
        [General]
        CPUCore = 1
        [Controls]
        ButtonPreference = \(PPSSPPHostConfig.buttonPreferenceCross)
        """.write(to: iniURL, atomically: true, encoding: .utf8)

        XCTAssertFalse(PPSSPPHostConfig.memstickIniLooksCurrent(try String(contentsOf: iniURL, encoding: .utf8)))
        try PPSSPPHostConfig.ensureMemstickDefaults(at: root, fileManager: fm)
        let repaired = try String(contentsOf: iniURL, encoding: .utf8)
        XCTAssertTrue(PPSSPPHostConfig.memstickIniLooksCurrent(repaired))
        XCTAssertTrue(repaired.contains("CPUCore = \(PPSSPPDefaults.appStoreCPUCore.rawValue)"))
    }

    func testBatterySaveReloadTargetsSystemsWithLiveBatteryIO() {
        XCTAssertTrue(BatterySaveReload.shouldReloadAfterImport(for: .gba))
        XCTAssertTrue(BatterySaveReload.shouldReloadAfterImport(for: .psp))
        XCTAssertTrue(BatterySaveReload.shouldReloadAfterImport(for: .n64))
        XCTAssertTrue(BatterySaveReload.shouldReloadAfterImport(for: .nds))
    }

    /// `sceUtilitySavedata` draws labels and button icons through PPGe. Upstream
    /// `__PPGeInit` skips `ppge_atlas.zim` when `SYSPROP_IS_HEADLESS` is true.
    /// Official iOS and libretro report that property false; only the headless
    /// harness returns true. `CoreParameter.headLess` must stay true so RetroPlay
    /// does not tick the PPSSPP XMB (`NativeFrame` stays a no-op).
    func testSavedataDialogPPGeAtlasIsLoadedWithoutStartingTheFrontend() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let stub = try String(
            contentsOf: root.appendingPathComponent("AppHost/Sources/RetroPlayPPSSPPSystemStubs.mm"),
            encoding: .utf8
        )
        XCTAssertFalse(
            stub.contains("SYSPROP_IS_HEADLESS: return true"),
            "Headless=true skips the PPGe atlas, so SAVEDATA create/load text and button icons never draw"
        )
        XCTAssertTrue(
            stub.contains("rp_ppsspp_reports_system_headless"),
            "The stub must follow the tested host policy instead of a hardcoded headless harness"
        )
        XCTAssertTrue(stub.contains("void NativeFrame(GraphicsContext *) {}"))

        let bridge = try String(
            contentsOf: root.appendingPathComponent("AppHost/Sources/RetroPlayPPSSPPBridge.mm"),
            encoding: .utf8
        )
        XCTAssertTrue(bridge.contains("param.headLess = true"))
        XCTAssertTrue(bridge.contains("retroPlayBundledPPSSPPAssetsDirectory"))
        XCTAssertTrue(bridge.contains("ppge_atlas.zim"))

        let assets = root.appendingPathComponent("AppHost/Supporting/assets", isDirectory: true)
        let zim = assets.appendingPathComponent(PPSSPPHostConfig.ppgeAtlasFileName)
        let meta = assets.appendingPathComponent(PPSSPPHostConfig.ppgeAtlasMetaFileName)
        XCTAssertEqual(try sha256Hex(of: zim), PPSSPPHostConfig.ppgeAtlasSHA256)
        XCTAssertEqual(try sha256Hex(of: meta), PPSSPPHostConfig.ppgeAtlasMetaSHA256)
        XCTAssertFalse(PPSSPPHostConfig.reportsSystemHeadless)
        XCTAssertTrue(PPSSPPHostConfig.coreParameterHeadLess)
        XCTAssertTrue(PPSSPPHostConfig.utilityDialogLabelsCanDraw(atlasBundled: true))
        XCTAssertFalse(PPSSPPHostConfig.utilityDialogLabelsCanDraw(atlasBundled: false))
    }

    func testCreateSaveHonorsGameButtonSwap() {
        XCTAssertEqual(PSPSavedataDialogPolicy.initialYesNoChoice(for: .createNew), 1)
        XCTAssertEqual(
            PSPSavedataDialogPolicy.result(step: .createNew, buttonSwap: 1, pressedCross: true, pressedCircle: false),
            .startSave
        )
        XCTAssertEqual(
            PSPSavedataDialogPolicy.result(step: .createNew, buttonSwap: 0, pressedCross: true, pressedCircle: false),
            .cancel
        )
        XCTAssertEqual(
            PSPSavedataDialogPolicy.result(step: .createNew, buttonSwap: 0, pressedCross: false, pressedCircle: true),
            .startSave
        )

        XCTAssertEqual(PSPSavedataDialogPolicy.initialYesNoChoice(for: .createOverwrite), 0)
        XCTAssertEqual(
            PSPSavedataDialogPolicy.result(step: .createOverwrite, buttonSwap: 1, pressedCross: true, pressedCircle: false),
            .cancel
        )
        XCTAssertEqual(
            PSPSavedataDialogPolicy.result(
                step: .createOverwrite,
                buttonSwap: 1,
                pressedCross: true,
                pressedCircle: false,
                yesnoChoice: 1
            ),
            .startSave
        )
    }

    func testLoadSaveHonorsGameButtonSwap() {
        XCTAssertEqual(PSPSavedataDialogPolicy.initialYesNoChoice(for: .loadConfirm), 1)
        XCTAssertEqual(
            PSPSavedataDialogPolicy.result(step: .loadConfirm, buttonSwap: 1, pressedCross: true, pressedCircle: false),
            .startLoad
        )
        XCTAssertEqual(
            PSPSavedataDialogPolicy.result(step: .loadConfirm, buttonSwap: 0, pressedCross: true, pressedCircle: false),
            .cancel
        )
        XCTAssertEqual(
            PSPSavedataDialogPolicy.result(step: .loadConfirm, buttonSwap: 0, pressedCross: false, pressedCircle: true),
            .startLoad
        )

        XCTAssertEqual(
            PSPSavedataDialogPolicy.result(step: .loadList, buttonSwap: 1, pressedCross: true, pressedCircle: false),
            .startLoad
        )
        XCTAssertEqual(
            PSPSavedataDialogPolicy.result(step: .loadList, buttonSwap: 1, pressedCross: false, pressedCircle: true),
            .cancel
        )
        XCTAssertEqual(
            PSPSavedataDialogPolicy.result(step: .loadNoData, buttonSwap: 1, pressedCross: true, pressedCircle: false),
            .none
        )
        XCTAssertEqual(
            PSPSavedataDialogPolicy.result(step: .loadNoData, buttonSwap: 1, pressedCross: false, pressedCircle: true),
            .noData
        )
        XCTAssertEqual(
            PSPSavedataDialogPolicy.result(step: .loadNoData, buttonSwap: 0, pressedCross: true, pressedCircle: false),
            .noData
        )
    }
}

private func sha256Hex(of url: URL) throws -> String {
    let data = try Data(contentsOf: url)
    return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}
