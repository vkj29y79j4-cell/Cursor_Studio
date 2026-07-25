import ApplicationServices
import CoreGraphics
import Darwin
import Foundation

// This proof of concept uses API names documented by Mousecape, but the
// implementation below is original. See THIRD_PARTY_NOTICES.md.

private typealias ConnectionFunction = @convention(c) () -> Int32
private typealias RegisterCursorFunction = @convention(c) (
    Int32,
    UnsafeMutablePointer<CChar>,
    Bool,
    Bool,
    CGSize,
    CGPoint,
    UInt,
    CGFloat,
    CFArray,
    UnsafeMutablePointer<Int32>
) -> Int32
private typealias RemoveCursorFunction = @convention(c) (
    Int32,
    UnsafeMutablePointer<CChar>,
    Bool
) -> Int32
private typealias CreateCursorImageFunction = @convention(c) (
    Int32,
    UnsafeMutablePointer<CChar>,
    UnsafeMutablePointer<CGPoint>
) -> Unmanaged<CGImage>?
private typealias CopyCursorImagesFunction = @convention(c) (
    Int32,
    UnsafeMutablePointer<CChar>,
    UnsafeMutablePointer<CGSize>,
    UnsafeMutablePointer<CGPoint>,
    UnsafeMutablePointer<UInt>,
    UnsafeMutablePointer<CGFloat>,
    UnsafeMutablePointer<Unmanaged<CFArray>?>
) -> Int32
private typealias UnregisterAllFunction = @convention(c) (Int32) -> Int32
private typealias SetCoreCursorFunction = @convention(c) (Int32, Int32) -> Int32
private typealias CursorNameFunction = @convention(c) (Int32) -> UnsafePointer<CChar>?
private typealias DockCursorOverrideFunction = @convention(c) (Int32, Bool) -> Void

private enum ProofError: LocalizedError {
    case symbolUnavailable([String])
    case imageCreationFailed
    case registrationFailed(Int32)
    case verificationFailed
    case restorationFailed(Int32)

    var errorDescription: String? {
        switch self {
        case .symbolUnavailable(let names):
            "Private cursor API unavailable: \(names.joined(separator: " / "))"
        case .imageCreationFailed:
            "Could not create the proof cursor image."
        case .registrationFailed(let code):
            "Global cursor registration failed with CGError \(code)."
        case .verificationFailed:
            "The registered global Arrow cursor did not match the proof image."
        case .restorationFailed(let code):
            "Restoring the system cursor failed with CGError \(code)."
        }
    }
}

private final class DynamicCursorAPI {
    private var handles: [UnsafeMutableRawPointer] = []

    let mainConnection: ConnectionFunction
    let registerCursor: RegisterCursorFunction
    let removeCursor: RemoveCursorFunction
    let createCursorImage: CreateCursorImageFunction
    let copyCursorImages: CopyCursorImagesFunction
    let unregisterAll: UnregisterAllFunction
    let setCoreCursor: SetCoreCursorFunction
    let cursorName: CursorNameFunction
    let setDockCursorOverride: DockCursorOverrideFunction

    init() throws {
        let frameworkPaths = [
            "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics",
            "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight",
            "/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices",
            "/System/Library/Frameworks/ApplicationServices.framework/Frameworks/HIServices.framework/HIServices",
        ]

        handles = frameworkPaths.compactMap { dlopen($0, RTLD_LAZY | RTLD_LOCAL) }
        handles.append(dlopen(nil, RTLD_LAZY | RTLD_LOCAL))

        mainConnection = try Self.load(
            ["CGSMainConnectionID", "SLSMainConnectionID"],
            from: handles,
            as: ConnectionFunction.self
        )
        registerCursor = try Self.load(
            ["CGSRegisterCursorWithImages", "SLSRegisterCursorWithImages"],
            from: handles,
            as: RegisterCursorFunction.self
        )
        removeCursor = try Self.load(
            ["CGSRemoveRegisteredCursor", "SLSRemoveRegisteredCursor"],
            from: handles,
            as: RemoveCursorFunction.self
        )
        createCursorImage = try Self.load(
            ["CGSCreateRegisteredCursorImage", "SLSCreateRegisteredCursorImage"],
            from: handles,
            as: CreateCursorImageFunction.self
        )
        copyCursorImages = try Self.load(
            ["CGSCopyRegisteredCursorImages", "SLSCopyRegisteredCursorImages"],
            from: handles,
            as: CopyCursorImagesFunction.self
        )
        unregisterAll = try Self.load(
            ["CoreCursorUnregisterAll"],
            from: handles,
            as: UnregisterAllFunction.self
        )
        setCoreCursor = try Self.load(
            ["CoreCursorSet"],
            from: handles,
            as: SetCoreCursorFunction.self
        )
        cursorName = try Self.load(
            ["CGSCursorNameForSystemCursor", "SLSCursorNameForSystemCursor"],
            from: handles,
            as: CursorNameFunction.self
        )
        setDockCursorOverride = try Self.load(
            ["CGSSetDockCursorOverride", "SLSSetDockCursorOverride"],
            from: handles,
            as: DockCursorOverrideFunction.self
        )
    }

    deinit {
        for handle in handles {
            dlclose(handle)
        }
    }

    private static func load<T>(
        _ names: [String],
        from handles: [UnsafeMutableRawPointer],
        as type: T.Type
    ) throws -> T {
        for name in names {
            for handle in handles {
                if let symbol = dlsym(handle, name) {
                    return unsafeBitCast(symbol, to: type)
                }
            }
        }
        throw ProofError.symbolUnavailable(names)
    }
}

private let arrowIdentifier = "com.apple.coregraphics.Arrow"
private let cursorPixelSize = 64
private let cursorPointSize = CGSize(width: 64, height: 64)

private func makeProofCursor() throws -> CGImage {
    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(
              data: nil,
              width: cursorPixelSize,
              height: cursorPixelSize,
              bitsPerComponent: 8,
              bytesPerRow: cursorPixelSize * 4,
              space: colorSpace,
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
          ) else {
        throw ProofError.imageCreationFailed
    }

    context.clear(CGRect(x: 0, y: 0, width: cursorPixelSize, height: cursorPixelSize))
    context.setShouldAntialias(true)
    context.setAllowsAntialiasing(true)
    context.translateBy(x: 0, y: CGFloat(cursorPixelSize))
    context.scaleBy(x: 1, y: -1)

    let pointer = CGMutablePath()
    pointer.move(to: CGPoint(x: 4, y: 3))
    pointer.addLine(to: CGPoint(x: 4, y: 52))
    pointer.addLine(to: CGPoint(x: 17, y: 40))
    pointer.addLine(to: CGPoint(x: 27, y: 61))
    pointer.addLine(to: CGPoint(x: 38, y: 56))
    pointer.addLine(to: CGPoint(x: 28, y: 36))
    pointer.addLine(to: CGPoint(x: 47, y: 34))
    pointer.closeSubpath()

    context.addPath(pointer)
    context.setFillColor(CGColor(red: 1, green: 0.05, blue: 0.65, alpha: 1))
    context.fillPath()
    context.addPath(pointer)
    context.setStrokeColor(CGColor(gray: 0.05, alpha: 1))
    context.setLineWidth(4)
    context.setLineJoin(.round)
    context.strokePath()

    guard let image = context.makeImage() else {
        throw ProofError.imageCreationFailed
    }
    return image
}

private func containsProofColor(_ image: CGImage) -> Bool {
    let width = image.width
    let height = image.height
    var pixels = [UInt8](repeating: 0, count: width * height * 4)

    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(
              data: &pixels,
              width: width,
              height: height,
              bitsPerComponent: 8,
              bytesPerRow: width * 4,
              space: colorSpace,
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
          ) else {
        return false
    }

    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

    return stride(from: 0, to: pixels.count, by: 4).contains { offset in
        let red = pixels[offset]
        let green = pixels[offset + 1]
        let blue = pixels[offset + 2]
        let alpha = pixels[offset + 3]
        return red > 200 && green < 80 && blue > 100 && alpha > 200
    }
}

private func withMutableCString<T>(
    _ string: String,
    _ body: (UnsafeMutablePointer<CChar>) throws -> T
) rethrows -> T {
    var bytes = Array(string.utf8CString)
    return try bytes.withUnsafeMutableBufferPointer { buffer in
        try body(buffer.baseAddress!)
    }
}

private func arrowIdentifiers(using api: DynamicCursorAPI) -> [String] {
    var result = [arrowIdentifier, "com.apple.coregraphics.ArrowCtx"]

    for cursorID in 0..<128 {
        guard let rawName = api.cursorName(Int32(cursorID)) else {
            continue
        }
        let name = String(cString: rawName)
        if name.localizedCaseInsensitiveContains("arrow"), !result.contains(name) {
            result.append(name)
        }
    }

    return result
}

private func restoreDefault(
    using api: DynamicCursorAPI,
    connection: Int32,
    registeredNames: [String]
) throws {
    for name in registeredNames {
        _ = withMutableCString(name) { identifier in
            api.removeCursor(connection, identifier, false)
        }
    }

    let result = api.unregisterAll(connection)
    guard result == 0 else {
        throw ProofError.restorationFailed(result)
    }

    // Re-register every system-defined cursor. Mousecape uses the same 0...44
    // range after unregistering overrides.
    for cursorID in 0...44 {
        _ = api.setCoreCursor(connection, Int32(cursorID))
    }
}

private func runProof(holdSeconds: TimeInterval) throws {
    let api = try DynamicCursorAPI()
    let connection = api.mainConnection()
    let proofImage = try makeProofCursor()
    let identifiers = arrowIdentifiers(using: api)

    print("Resolved private cursor symbols.")
    print("Main window-server connection: \(connection)")
    print("Arrow identifiers: \(identifiers.joined(separator: ", "))")

    var registeredNames: [String] = []
    var lastSeed: Int32 = 0

    for name in identifiers {
        var seed: Int32 = 0
        let result = withMutableCString(name) { identifier in
            api.registerCursor(
                connection,
                identifier,
                true,
                true,
                cursorPointSize,
                CGPoint(x: 4, y: 4),
                1,
                1,
                [proofImage] as CFArray,
                &seed
            )
        }
        if result == 0 {
            registeredNames.append(name)
            lastSeed = seed
        } else {
            print("Registration for \(name) returned CGError \(result).")
        }
    }

    guard !registeredNames.isEmpty else {
        throw ProofError.registrationFailed(-1)
    }
    api.setDockCursorOverride(connection, false)

    defer {
        do {
            try restoreDefault(
                using: api,
                connection: connection,
                registeredNames: registeredNames
            )
            print("RESTORED: macOS system cursors were re-registered.")
        } catch {
            fputs("RESTORE ERROR: \(error.localizedDescription)\n", stderr)
        }
    }

    var verifiedName: String?
    var verifiedSize: CGSize?
    var verifiedHotspot: CGPoint?

    for name in registeredNames {
        var copiedSize = CGSize.zero
        var copiedHotspot = CGPoint.zero
        var copiedFrameCount: UInt = 0
        var copiedFrameDuration: CGFloat = 0
        var copiedImages: Unmanaged<CFArray>?
        let copyResult = withMutableCString(name) { identifier in
            api.copyCursorImages(
                connection,
                identifier,
                &copiedSize,
                &copiedHotspot,
                &copiedFrameCount,
                &copiedFrameDuration,
                &copiedImages
            )
        }

        if copyResult == 0, let copiedImages {
            let images = copiedImages.takeRetainedValue()
            print(
                "Copied \(CFArrayGetCount(images)) representation(s) for \(name): "
                    + "size \(copiedSize), hotspot \(copiedHotspot), "
                    + "frames \(copiedFrameCount)."
            )
            for index in 0..<CFArrayGetCount(images) {
                guard let pointer = CFArrayGetValueAtIndex(images, index) else {
                    continue
                }
                let image = Unmanaged<CGImage>.fromOpaque(pointer).takeUnretainedValue()
                if containsProofColor(image) {
                    verifiedName = name
                    verifiedSize = CGSize(width: image.width, height: image.height)
                    verifiedHotspot = copiedHotspot
                    break
                }
            }
        } else {
            print("Copying \(name) returned CGError \(copyResult).")
        }
        if verifiedName != nil {
            break
        }

        var registeredHotspot = CGPoint.zero
        let registeredImage = withMutableCString(name) { identifier in
            api.createCursorImage(connection, identifier, &registeredHotspot)?
                .takeRetainedValue()
        }

        if let registeredImage, containsProofColor(registeredImage) {
            verifiedName = name
            verifiedSize = CGSize(
                width: registeredImage.width,
                height: registeredImage.height
            )
            verifiedHotspot = registeredHotspot
            break
        }
    }

    guard let verifiedName, let verifiedSize, let verifiedHotspot else {
        throw ProofError.verificationFailed
    }

    print(
        "WindowServer returned \(Int(verifiedSize.width))x\(Int(verifiedSize.height)), "
            + "hotspot \(verifiedHotspot), for \(verifiedName)."
    )
    print("APPLIED: global Arrow registration succeeded (seed \(lastSeed)).")
    print("VERIFIED: WindowServer's Arrow image contains the proof artwork.")
    print("The neon-pink Arrow will remain active for \(holdSeconds) seconds.")
    Thread.sleep(forTimeInterval: holdSeconds)
}

let requestedHold = CommandLine.arguments
    .dropFirst()
    .first
    .flatMap(TimeInterval.init) ?? 8
let holdSeconds = min(max(requestedHold, 1), 60)

do {
    try runProof(holdSeconds: holdSeconds)
} catch {
    fputs("PROOF FAILED: \(error.localizedDescription)\n", stderr)
    exit(EXIT_FAILURE)
}
