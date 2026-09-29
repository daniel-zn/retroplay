// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Host-side PPSSPP memstick / dialog settings RetroPlay must apply before `PSP_Init`.
///
/// `sceUtilityGetSystemParamInt(BUTTON_PREFERENCE)` returns `iButtonPreference`. Games
/// that follow the PSP SDK copy that into `common.buttonSwap` before
/// `sceUtilitySavedataInitStart`. `PSPDialog::UpdateCommon()` maps the game's
/// `buttonSwap`, not the host preference. Set the preference before boot so a
/// compliant game writes Cross; do not overwrite a game that writes something else.
public enum PPSSPPHostConfig: Sendable {
    public static let buttonPreferenceCross = PPSSPPDefaults.buttonPreferenceCross
    public static let memStickSizeGB = 16

    /// `SYSPROP_IS_HEADLESS`. Official iOS and libretro report false. The headless
    /// harness reports true, and `__PPGeInit` then skips `ppge_atlas.zim`, which is
    /// what draws SAVEDATA labels and button icons. Colored rects still draw either way.
    public static let reportsSystemHeadless = false

    /// `CoreParameter.headLess`. Stays true so RetroPlay does not run the PPSSPP XMB.
    /// `__PPGeInit` then sets `textDrawerInited` and leaves `textDrawer` null, so utility
    /// text uses atlas glyphs. Those glyphs are only legible on the software GPU when
    /// `enablesSoftwareRenderer` is applied to `g_Config.bSoftwareRendering` — that is
    /// the flag `PPGeDrawCurrentText` checks before splitting the 2048 atlas into 512 windows.
    public static let coreParameterHeadLess = true

    /// `g_Config.bSoftwareRendering`. RetroPlay already selects `GPUCORE_SOFTWARE`, but
    /// PPGe texture windows follow this flag, not the GPU core enum. The software
    /// rasterizer clamps texel coordinates to 511 when a texture is larger than 512.
    /// The bundled atlas is 2048×2048 and Ubuntu glyphs sit outside that box, so leaving
    /// the flag false samples the clamp edge and the savedata labels look garbled.
    public static let enablesSoftwareRenderer = true

    public static let ppgeAtlasFileName = "ppge_atlas.zim"
    public static let ppgeAtlasMetaFileName = "ppge_atlas.meta"

    public static let ppgeAtlasSHA256 = "3ab7fcf6956d0281ada94d501fc6d1cfa8fc034f139e25fed6c829f723d92a95"
    public static let ppgeAtlasMetaSHA256 = "2eadb18c05d8f492b46c23bcbad4f4811c98cf717145536ccfe136787845f2ed"

    /// Labels and icons require the atlas. `coreParameterHeadLess` does not block them.
    /// Legibility of the labels also requires `enablesSoftwareRenderer` when the atlas
    /// is larger than the software texture limit. See `PPGeAtlasText`.
    public static func utilityDialogLabelsCanDraw(atlasBundled: Bool) -> Bool {
        atlasBundled && !reportsSystemHeadless
    }

    /// True when atlas glyphs are sampled from their real texels instead of the 512 clamp.
    public static func utilityDialogTextIsLegible(atlasWidth: Int, atlasHeight: Int) -> Bool {
        guard !reportsSystemHeadless else { return false }
        let needsTextureWindows = atlasWidth > PPGeAtlasText.softwareTextureLimit
            || atlasHeight > PPGeAtlasText.softwareTextureLimit
        return !needsTextureWindows || enablesSoftwareRenderer
    }

    /// True when a game that copies this system param into `buttonSwap` gets Cross as OK.
    public static func savedataDialogUsesCrossAsOK(buttonPreference: Int) -> Bool {
        buttonPreference == buttonPreferenceCross
    }

    public static let requiredMemstickSubpaths = [
        "PSP/SAVEDATA",
        "PSP/GAME",
        "PSP/SYSTEM",
    ]

    public static func memstickLooksReady(at memstickRoot: URL, fileManager: FileManager = .default) -> Bool {
        requiredMemstickSubpaths.allSatisfy { sub in
            fileManager.fileExists(
                atPath: memstickRoot.appendingPathComponent(sub, isDirectory: true).path
            )
        }
    }

    /// Minimal memstick `ppsspp.ini` so a stale sandbox copy cannot revert Cross-as-confirm
    /// or the App Store IR core before `applyRetroPlayHostConfig` runs in the native bridge.
    public static func ensureMemstickDefaults(
        at memstickRoot: URL,
        fileManager: FileManager = .default
    ) throws {
        try fileManager.createDirectory(at: memstickRoot, withIntermediateDirectories: true)
        for sub in requiredMemstickSubpaths {
            try fileManager.createDirectory(
                at: memstickRoot.appendingPathComponent(sub, isDirectory: true),
                withIntermediateDirectories: true
            )
        }

        let iniURL = memstickRoot.appendingPathComponent("ppsspp.ini")
        let desired = memstickIniContents
        if fileManager.fileExists(atPath: iniURL.path),
           let existing = try? String(contentsOf: iniURL, encoding: .utf8),
           memstickIniLooksCurrent(existing) {
            return
        }
        try desired.write(to: iniURL, atomically: true, encoding: .utf8)
    }

    /// Both Cross-as-confirm and the App Store IR core must be present — stale sandbox copies
    /// sometimes keep the right button map but still request JIT.
    public static func memstickIniLooksCurrent(_ contents: String) -> Bool {
        contents.contains("ButtonPreference = \(buttonPreferenceCross)")
            && contents.contains("\(PPSSPPDefaults.iniKey) = \(PPSSPPDefaults.appStoreCPUCore.rawValue)")
    }

    public static var memstickIniContents: String {
        """
        [General]
        \(PPSSPPDefaults.iniKey) = \(PPSSPPDefaults.appStoreCPUCore.rawValue)

        [Controls]
        ButtonPreference = \(buttonPreferenceCross)

        """
    }
}

/// Called from `RetroPlayPPSSPPSystemStubs.mm`. Must stay a C ABI bool.
@_cdecl("rp_ppsspp_reports_system_headless")
public func rp_ppsspp_reports_system_headless() -> CBool {
    PPSSPPHostConfig.reportsSystemHeadless
}

/// Called from `RetroPlayPPSSPPBridge.mm` so PPGe atlas text uses 512 texture windows.
@_cdecl("rp_ppsspp_enables_software_renderer")
public func rp_ppsspp_enables_software_renderer() -> CBool {
    PPSSPPHostConfig.enablesSoftwareRenderer
}
