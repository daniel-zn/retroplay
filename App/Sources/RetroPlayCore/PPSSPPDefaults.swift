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
}
