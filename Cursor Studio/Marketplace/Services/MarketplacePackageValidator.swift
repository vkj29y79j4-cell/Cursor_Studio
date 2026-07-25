import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

actor MarketplacePackageValidator {
    private static let maximumArchiveBytes = 64 * 1_024 * 1_024
    private static let maximumUncompressedBytes = 128 * 1_024 * 1_024
    private static let maximumFileCount = 256
    private static let maximumManifestBytes = 1 * 1_024 * 1_024
    private static let maximumDecodedPixels = 32_000_000

    private let fileManager: FileManager
    private let stagingDirectory: URL

    init(paths: ApplicationPaths, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        stagingDirectory = paths.importStagingDirectory
    }

    func validatePackage(
        at sourceURL: URL,
        expectedSHA256: String? = nil
    ) throws -> ValidatedMarketplacePackage {
        let values = try sourceURL.resourceValues(
            forKeys: [.isDirectoryKey, .isRegularFileKey, .fileSizeKey]
        )
        if values.isDirectory == true {
            let manifest = try validateExtractedTree(at: sourceURL)
            return ValidatedMarketplacePackage(
                rootDirectory: sourceURL,
                cleanupDirectory: sourceURL,
                manifest: manifest,
                sha256: nil
            )
        }
        guard values.isRegularFile == true,
              (values.fileSize ?? Self.maximumArchiveBytes + 1)
                <= Self.maximumArchiveBytes else {
            throw invalid("Package size is outside the allowed limit.")
        }

        let archiveData = try Data(contentsOf: sourceURL, options: .mappedIfSafe)
        let digest = SHA256.hash(data: archiveData)
            .map { String(format: "%02x", $0) }
            .joined()
        if let expectedSHA256,
           digest.caseInsensitiveCompare(expectedSHA256) != .orderedSame {
            throw invalid("The SHA-256 checksum does not match.")
        }
        try inspectZIPCentralDirectory(archiveData)

        try fileManager.createDirectory(
            at: stagingDirectory,
            withIntermediateDirectories: true
        )
        let extractionDirectory = stagingDirectory.appending(
            path: "Marketplace-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try fileManager.createDirectory(
            at: extractionDirectory,
            withIntermediateDirectories: true
        )
        do {
            try extractZIP(sourceURL, to: extractionDirectory)
            let manifest = try validateExtractedTree(at: extractionDirectory)
            return ValidatedMarketplacePackage(
                rootDirectory: extractionDirectory,
                cleanupDirectory: extractionDirectory,
                manifest: manifest,
                sha256: digest
            )
        } catch {
            try? fileManager.removeItem(at: extractionDirectory)
            throw error
        }
    }

    private func inspectZIPCentralDirectory(_ data: Data) throws {
        guard let eocd = endOfCentralDirectoryOffset(in: data),
              data.uint32LE(at: eocd) == 0x0605_4B50 else {
            throw invalid("The ZIP directory is missing.")
        }
        let entryCount = Int(data.uint16LE(at: eocd + 10))
        let centralSize = Int(data.uint32LE(at: eocd + 12))
        let centralOffset = Int(data.uint32LE(at: eocd + 16))
        guard entryCount > 0,
              entryCount <= Self.maximumFileCount,
              centralOffset >= 0,
              centralSize >= 0,
              centralOffset + centralSize <= data.count else {
            throw invalid("The ZIP directory is outside the allowed limits.")
        }

        var offset = centralOffset
        var uncompressedTotal: UInt64 = 0
        var normalizedPaths: Set<String> = []
        for _ in 0..<entryCount {
            guard offset + 46 <= data.count,
                  data.uint32LE(at: offset) == 0x0201_4B50 else {
                throw invalid("A ZIP entry is malformed.")
            }
            let flags = data.uint16LE(at: offset + 8)
            let method = data.uint16LE(at: offset + 10)
            let uncompressedSize = UInt64(data.uint32LE(at: offset + 24))
            let nameLength = Int(data.uint16LE(at: offset + 28))
            let extraLength = Int(data.uint16LE(at: offset + 30))
            let commentLength = Int(data.uint16LE(at: offset + 32))
            let externalAttributes = data.uint32LE(at: offset + 38)
            let end = offset + 46 + nameLength + extraLength + commentLength
            guard nameLength > 0, end <= data.count else {
                throw invalid("A ZIP entry name is malformed.")
            }
            guard flags & 0x1 == 0 else {
                throw invalid("Encrypted ZIP entries are not supported.")
            }
            guard method == 0 || method == 8 else {
                throw invalid("Only Store and Deflate compression are supported.")
            }
            guard let name = String(
                data: data[(offset + 46)..<(offset + 46 + nameLength)],
                encoding: .utf8
            ) else {
                throw invalid("ZIP paths must use UTF-8.")
            }
            let isDirectoryEntry = name.hasSuffix("/")
            let validatedName = isDirectoryEntry
                ? String(name.dropLast())
                : name
            try validateRelativePath(validatedName)

            let unixMode = UInt16((externalAttributes >> 16) & 0xffff)
            let fileType = unixMode & 0o170000
            guard fileType != 0o120000,
                  fileType != 0o060000,
                  fileType != 0o020000,
                  fileType != 0o010000,
                  (isDirectoryEntry || unixMode & 0o111 == 0) else {
                throw invalid("Links, devices, and executable files are not allowed.")
            }

            let folded = validatedName
                .precomposedStringWithCanonicalMapping
                .lowercased()
            guard normalizedPaths.insert(folded).inserted else {
                throw invalid("The package contains duplicate paths.")
            }
            uncompressedTotal += uncompressedSize
            guard uncompressedTotal <= Self.maximumUncompressedBytes else {
                throw invalid("The expanded package is too large.")
            }
            offset = end
        }
        guard offset <= centralOffset + centralSize else {
            throw invalid("The ZIP directory size is inconsistent.")
        }
    }

    private func endOfCentralDirectoryOffset(in data: Data) -> Int? {
        guard data.count >= 22 else { return nil }
        let lowerBound = max(0, data.count - 65_557)
        for offset in stride(from: data.count - 22, through: lowerBound, by: -1)
            where data.uint32LE(at: offset) == 0x0605_4B50 {
            return offset
        }
        return nil
    }

    private func extractZIP(_ sourceURL: URL, to destination: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = [
            "-x",
            "-k",
            "--noqtn",
            sourceURL.path,
            destination.path,
        ]
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw invalid("The ZIP archive could not be extracted.")
        }
    }

    private func validateExtractedTree(
        at root: URL
    ) throws -> MarketplacePackageManifest {
        let standardizedRoot = root.standardizedFileURL
        guard let enumerator = fileManager.enumerator(
            at: standardizedRoot,
            includingPropertiesForKeys: [
                .isRegularFileKey,
                .isDirectoryKey,
                .isSymbolicLinkKey,
                .fileSizeKey,
            ],
            options: [],
            errorHandler: { _, _ in false }
        ) else {
            throw invalid("The package directory cannot be read.")
        }

        var files: [String: URL] = [:]
        var totalBytes = 0
        var itemCount = 0
        while let url = enumerator.nextObject() as? URL {
            itemCount += 1
            guard itemCount <= Self.maximumFileCount else {
                throw invalid("The package contains too many files.")
            }
            let relative = url.standardizedFileURL.pathComponents
                .dropFirst(standardizedRoot.pathComponents.count)
                .joined(separator: "/")
            try validateRelativePath(relative)
            let values = try url.resourceValues(
                forKeys: [
                    .isRegularFileKey,
                    .isDirectoryKey,
                    .isSymbolicLinkKey,
                    .fileSizeKey,
                ]
            )
            guard values.isSymbolicLink != true else {
                throw invalid("Symbolic links are not allowed.")
            }
            if values.isDirectory == true {
                guard relative == "Assets" else {
                    throw invalid("Unexpected package directory: \(relative)")
                }
                continue
            }
            guard values.isRegularFile == true,
                  relative == "manifest.json"
                    || (
                        relative.hasPrefix("Assets/")
                        && relative.split(separator: "/").count == 2
                        && url.pathExtension.lowercased() == "png"
                    ) else {
                throw invalid("Unexpected package file: \(relative)")
            }
            let attributes = try fileManager.attributesOfItem(atPath: url.path)
            let permissions = (
                attributes[.posixPermissions] as? NSNumber
            )?.uint16Value ?? 0
            guard permissions & 0o111 == 0 else {
                throw invalid("Executable files are not allowed.")
            }
            totalBytes += values.fileSize ?? 0
            guard totalBytes <= Self.maximumUncompressedBytes else {
                throw invalid("The expanded package is too large.")
            }
            let folded = relative.precomposedStringWithCanonicalMapping
                .lowercased()
            guard files[folded] == nil else {
                throw invalid("The package contains duplicate paths.")
            }
            files[folded] = url
        }

        guard let manifestURL = files["manifest.json"],
              let manifestData = try? Data(contentsOf: manifestURL),
              manifestData.count <= Self.maximumManifestBytes,
              let manifest = try? JSONDecoder().decode(
                MarketplacePackageManifest.self,
                from: manifestData
              ),
              manifest.schemaVersion == 1,
              !manifest.name.trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty,
              !manifest.cursors.isEmpty,
              manifest.cursors.count <= CursorRole.allCases.count else {
            throw invalid("manifest.json is missing or invalid.")
        }

        var roles: Set<CursorRole> = []
        var referencedAssets: Set<String> = []
        for cursor in manifest.cursors {
            guard let role = CursorRole(rawValue: cursor.role),
                  roles.insert(role).inserted,
                  cursor.hotspotX.isFinite,
                  cursor.hotspotY.isFinite,
                  0...1 ~= cursor.hotspotX,
                  0...1 ~= cursor.hotspotY,
                  cursor.pointWidth.map({ $0.isFinite && $0 > 0 }) ?? true,
                  cursor.pointHeight.map({ $0.isFinite && $0 > 0 }) ?? true else {
                throw invalid("A cursor role or hotspot is invalid.")
            }
            try validateRelativePath(cursor.asset)
            let key = cursor.asset.precomposedStringWithCanonicalMapping
                .lowercased()
            guard key.hasPrefix("assets/"),
                  referencedAssets.insert(key).inserted,
                  let assetURL = files[key] else {
                throw invalid("A cursor asset is missing or duplicated.")
            }
            try validatePNG(
                at: assetURL,
                expectedWidth: cursor.pixelWidth,
                expectedHeight: cursor.pixelHeight
            )
        }
        return manifest
    }

    private func validatePNG(
        at url: URL,
        expectedWidth: Int,
        expectedHeight: Int
    ) throws {
        guard expectedWidth > 0,
              expectedHeight > 0,
              expectedHeight <= Self.maximumDecodedPixels,
              expectedWidth <= Self.maximumDecodedPixels / expectedHeight,
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetType(source) as String?
                == UTType.png.identifier,
              CGImageSourceGetCount(source) == 1,
              let properties = CGImageSourceCopyPropertiesAtIndex(
                source,
                0,
                nil
              ) as? [CFString: Any],
              (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue
                == expectedWidth,
              (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue
                == expectedHeight,
              let image = CGImageSourceCreateImageAtIndex(
                source,
                0,
                [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
              ),
              image.width == expectedWidth,
              image.height == expectedHeight else {
            throw invalid("A PNG asset failed image validation.")
        }
    }

    private func validateRelativePath(_ path: String) throws {
        guard !path.isEmpty,
              !path.hasPrefix("/"),
              !path.hasPrefix("\\"),
              !path.contains("\\"),
              !path.unicodeScalars.contains(where: {
                  CharacterSet.controlCharacters.contains($0)
              }) else {
            throw invalid("The package contains an unsafe path.")
        }
        let components = path.split(
            separator: "/",
            omittingEmptySubsequences: false
        )
        guard !components.isEmpty,
              components.allSatisfy({
                  !$0.isEmpty && $0 != "." && $0 != ".."
              }) else {
            throw invalid("The package contains an unsafe path.")
        }
    }

    private func invalid(_ reason: String) -> MarketplaceServiceError {
        .packageInvalid(
            L10n.text(
                reason,
                "Пакет содержит небезопасные или некорректные данные."
            )
        )
    }
}

nonisolated private extension Data {
    func uint16LE(at offset: Int) -> UInt16 {
        guard offset >= 0, offset + 2 <= count else { return 0 }
        return UInt16(self[offset])
            | UInt16(self[offset + 1]) << 8
    }

    func uint32LE(at offset: Int) -> UInt32 {
        guard offset >= 0, offset + 4 <= count else { return 0 }
        return UInt32(self[offset])
            | UInt32(self[offset + 1]) << 8
            | UInt32(self[offset + 2]) << 16
            | UInt32(self[offset + 3]) << 24
    }
}
