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

    /// Snippet for ppsspp.ini on App Store builds.
    public static var appStoreIniSnippet: String {
        "# RetroPlay App Store — JIT/dynarec off\n\(iniKey) = \(appStoreCPUCore.rawValue)\n"
    }

    public static let performanceNote = """
    Official PPSSPP App Store (2024-05-15): no JIT; IR-based caching interpreter;     nearly all PSP games run full speed on modern iOS. Heavy titles are edge cases for device QA — not sideload-only.
    """
}
