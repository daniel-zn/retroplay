// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Host-side model of upstream `PSPSaveDialog::Update` confirm branches.
///
/// `buttonSwap` is the game-written `pspUtilityDialogCommon.buttonSwap`.
/// `PSPDialog::UpdateCommon()` maps `buttonSwap == 1` to Cross as OK and Circle as
/// cancel. RetroPlay does not replace that field with its own control mapping.
/// A game that first copies `sceUtilityGetSystemParamInt(BUTTON_PREFERENCE)` will
/// see Cross, because the bridge sets that system param before boot.
public enum PSPSavedataDialogStep: Sendable, Equatable {
    /// `SCE_UTILITY_SAVEDATA_TYPE_SAVE` with no file yet. `yesnoChoice` stays 1 (Yes).
    case createNew
    /// Existing file. Init forces `yesnoChoice = 0` (No) before the overwrite prompt.
    case createOverwrite
    /// `SCE_UTILITY_SAVEDATA_TYPE_LISTLOAD`. OK starts the load with no Yes/No prompt.
    case loadList
    /// `SCE_UTILITY_SAVEDATA_TYPE_LOAD` when a file exists. `yesnoChoice` stays 1 (Yes).
    case loadConfirm
    /// `SCE_UTILITY_SAVEDATA_TYPE_LOAD` when nothing is on the memstick.
    case loadNoData
}

public enum PSPSavedataDialogResult: Sendable, Equatable {
    case startSave
    case startLoad
    case cancel
    /// Cancel on the empty-load screen (`SCE_UTILITY_SAVEDATA_ERROR_LOAD_NO_DATA`).
    case noData
    case none
}

public enum PSPSavedataDialogPolicy: Sendable {
    /// Upstream compares `common.buttonSwap` to the literal `1`, not to the host preference.
    public static func okIsCross(buttonSwap: Int) -> Bool {
        buttonSwap == 1
    }

    public static func initialYesNoChoice(for step: PSPSavedataDialogStep) -> Int {
        switch step {
        case .createOverwrite:
            return 0
        case .createNew, .loadConfirm, .loadList, .loadNoData:
            return 1
        }
    }

    /// Mirrors the `IsButtonPressed` order in `PSPSaveDialog::Update`: cancel is tested
    /// first, and OK on a Yes/No screen cancels when `yesnoChoice == 0`.
    public static func result(
        step: PSPSavedataDialogStep,
        buttonSwap: Int,
        pressedCross: Bool,
        pressedCircle: Bool,
        yesnoChoice: Int? = nil
    ) -> PSPSavedataDialogResult {
        let choice = yesnoChoice ?? initialYesNoChoice(for: step)
        let crossIsOK = okIsCross(buttonSwap: buttonSwap)
        let pressedOK = crossIsOK ? pressedCross : pressedCircle
        let pressedCancel = crossIsOK ? pressedCircle : pressedCross

        switch step {
        case .createNew, .createOverwrite:
            if pressedCancel || (pressedOK && choice == 0) {
                return .cancel
            }
            if pressedOK {
                return .startSave
            }
            return .none
        case .loadList:
            if pressedCancel {
                return .cancel
            }
            if pressedOK {
                return .startLoad
            }
            return .none
        case .loadConfirm:
            if pressedCancel || (pressedOK && choice == 0) {
                return .cancel
            }
            if pressedOK {
                return .startLoad
            }
            return .none
        case .loadNoData:
            if pressedCancel {
                return .noData
            }
            return .none
        }
    }
}
