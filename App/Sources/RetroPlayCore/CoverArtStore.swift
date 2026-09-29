// SPDX-License-Identifier: GPL-3.0-or-later
import CoreGraphics
import Foundation
import ImageIO

/// Cover art extracted from imported games, kept in Application Support/Covers so Files does
/// not show it. Local files only — never fetched.
/// Not marked Sendable: holds FileManager and is used from the main-actor UI / LibraryStore.
public struct CoverArtStore {
    public enum Origin: String, Sendable {
        case rom
        /// Marker written by the removed Todo-1 screenshot fallback.
        case frame
    }

    private let fileManager: FileManager
    public let coversDirectoryURL: URL

    /// Resolves the covers folder the same way as `SavePaths` for the given roots.
    public init(
        fileManager: FileManager = .default,
        documentsDirectoryURL: URL? = nil,
        supportDirectoryURL: URL? = nil
    ) {
        self.init(
            fileManager: fileManager,
            paths: SavePaths(
                fileManager: fileManager,
                documentsURL: documentsDirectoryURL,
                supportURL: supportDirectoryURL
            )
        )
    }

    public init(fileManager: FileManager = .default, paths: SavePaths) {
        self.fileManager = fileManager
        self.coversDirectoryURL = paths.coversDirectory
    }

    public func coverURL(forGameID id: UUID) -> URL {
        coversDirectoryURL.appendingPathComponent("\(id.uuidString).jpg")
    }

    public func originURL(forGameID id: UUID) -> URL {
        coversDirectoryURL.appendingPathComponent("\(id.uuidString).origin")
    }

    public func hasCover(forGameID id: UUID) -> Bool {
        fileManager.fileExists(atPath: coverURL(forGameID: id).path)
    }

    /// Legacy covers (no marker) and ROM artwork remain visible. Files left by
    /// the removed screenshot fallback stay identifiable for cleanup but are
    /// never returned to the library UI.
    public func displayableCoverURL(forGameID id: UUID) -> URL? {
        let url = coverURL(forGameID: id)
        guard origin(forGameID: id) != .frame,
              fileManager.fileExists(atPath: url.path)
        else { return nil }
        return url
    }

    public func origin(forGameID id: UUID) -> Origin? {
        guard let raw = try? String(contentsOf: originURL(forGameID: id), encoding: .utf8) else {
            return nil
        }
        return Origin(rawValue: raw.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    public func ensureDirectory() throws {
        try fileManager.createDirectory(at: coversDirectoryURL, withIntermediateDirectories: true)
    }

    public func removeCover(forGameID id: UUID) throws {
        let cover = coverURL(forGameID: id)
        if fileManager.fileExists(atPath: cover.path) {
            try fileManager.removeItem(at: cover)
        }
        let origin = originURL(forGameID: id)
        if fileManager.fileExists(atPath: origin.path) {
            try fileManager.removeItem(at: origin)
        }
    }

    /// Install cover from the imported game file when it already contains art.
    @discardableResult
    public func installFromGameFile(gameID: UUID, fileURL: URL, system: SystemID) throws -> Bool {
        guard let payload = CoverArtExtractor.extractImageData(from: fileURL, system: system),
              let jpeg = CoverArtJPEG.jpegData(fromImageFile: payload)
        else {
            return false
        }
        try write(jpeg, origin: .rom, forGameID: gameID)
        return true
    }

    private func write(_ jpeg: Data, origin: Origin, forGameID id: UUID) throws {
        try ensureDirectory()
        try jpeg.write(to: coverURL(forGameID: id), options: [.atomic])
        try origin.rawValue.write(to: originURL(forGameID: id), atomically: true, encoding: .utf8)
    }
}

enum CoverArtJPEG {
    static func jpegData(from image: CGImage, quality: CGFloat = 0.82) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            data,
            "public.jpeg" as CFString,
            1,
            nil
        ) else {
            return nil
        }
        let opts: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
        CGImageDestinationAddImage(dest, image, opts as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }

    static func jpegData(fromImageFile payload: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(payload as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            return nil
        }
        return jpegData(from: image)
    }
}
