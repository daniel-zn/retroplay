// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Validates that a PSP ROM's embedded product ID matches the library entry before loading saves.
public enum PSPROMOwnership: Sendable {
    public static func validate(romURL: URL, game: LibraryGame) throws {
        guard game.systemID == .psp else { return }
        guard let expected = game.pspProductID else { return }

        switch PSPProductIDExtractor.extract(from: romURL) {
        case .found(let actual):
            guard actual == expected else {
                throw EmulatorCoreError.romLoadFailed(
                    """
                    This ROM's product ID (\(actual)) does not match the library entry (\(expected)). \
                    Loading it could attach the wrong battery save.
                    """
                )
            }
        case .notFound, .unsupportedFormat:
            break
        }
    }
}
