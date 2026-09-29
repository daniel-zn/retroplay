// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// App Store–safe PPSSPP CPU defaults (no dynarec).
/// Mirrors upstream `CPUCore` in Core/ConfigValues.h.
public enum PPSSPPCPUCore: Int, Sendable {
    case interpreter = 0
    case jit = 1
    case irInterpreter = 2
    case jitIR = 3
}

public enum PPSSPPDefaults {
    /// Only legal App Store product path: IR caching interpreter.
    public static let appStoreCPUCore: PPSSPPCPUCore = .irInterpreter

    public static let dynarecAllowedOnAppStore = false

    public static let iniKey = "CPUCore"

    /// Upstream `PSP_SYSTEMPARAM_BUTTON_CROSS` (`Core/ConfigValues.h`). Games that call
    /// `sceUtilityGetSystemParamInt(PSP_SYSTEMPARAM_ID_INT_BUTTON_PREFERENCE)` copy this into
    /// `common.buttonSwap`. `PSPDialog::UpdateCommon()` reads that field (`buttonSwap == 1`
    /// means Cross is OK). A title that writes a different `buttonSwap` is left alone.
    /// The bridge sets `g_Config.iButtonPreference` on every `rp_ppsspp_load`, before boot,
    /// so the system param is Cross even if a stale ini said otherwise.
    public static let buttonPreferenceCross = 1

    /// Snippet for ppsspp.ini on App Store builds.
    public static var appStoreIniSnippet: String {
        "# RetroPlay App Store — JIT/dynarec off\n\(iniKey) = \(appStoreCPUCore.rawValue)\n"
    }

    public static let performanceNote = """
    Official PPSSPP App Store (2024-05-15): no JIT; IR-based caching interpreter;     nearly all PSP games run full speed on modern iOS. Heavy titles are edge cases for device QA — not sideload-only.
    """
}
