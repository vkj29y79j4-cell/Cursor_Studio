import AppKit
import ImageIO
import SwiftUI

nonisolated struct CursorAssetAnimation: Hashable, Sendable {
    let stripURL: URL
    let frameCount: Int
    let frameDuration: Double

    static func preview(
        for entry: CursorEntry,
        themeID: UUID,
        paths: ApplicationPaths
    ) -> CursorAssetAnimation? {
        guard entry.isAnimated,
              !entry.usesStaticAnimationFallback,
              entry.frameCount <= 24,
              let representation = entry.representations.min(by: {
                  let leftDistance = abs($0.scale - 2)
                  let rightDistance = abs($1.scale - 2)
                  if leftDistance == rightDistance {
                      return $0.scale > $1.scale
                  }
                  return leftDistance < rightDistance
              }),
              let stripURL = paths.assetURL(
                  themeID: themeID,
                  filename: representation.filename
              ) else {
            return nil
        }

        return CursorAssetAnimation(
            stripURL: stripURL,
            frameCount: entry.frameCount,
            frameDuration: max(entry.frameDuration, 1.0 / 60.0)
        )
    }
}

struct CursorAssetView: View {
    let url: URL?
    var animation: CursorAssetAnimation?
    var maximumSize: CGFloat = 72
    var fallbackSymbol = "cursorarrow"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if !reduceMotion,
               let animation,
               let frames = CursorImageCache.shared.frames(for: animation),
               !frames.isEmpty {
                TimelineView(
                    .animation(minimumInterval: animation.frameDuration)
                ) { context in
                    let elapsed = context.date.timeIntervalSinceReferenceDate
                    let frameIndex = Int(elapsed / animation.frameDuration)
                        % frames.count
                    cursorImage(frames[frameIndex])
                }
            } else if let url, let image = CursorImageCache.shared.image(for: url) {
                cursorImage(image)
            } else {
                Image(systemName: fallbackSymbol)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(.secondary)
                    .padding(maximumSize * 0.24)
            }
        }
        .frame(width: maximumSize, height: maximumSize)
        .accessibilityHidden(true)
    }

    private func cursorImage(_ image: NSImage) -> some View {
        Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
    }
}

@MainActor
enum CursorAnimationFrameLoader {
    static func loadImages(
        at url: URL,
        frameCount: Int
    ) -> [NSImage]? {
        guard (2...24).contains(frameCount),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let strip = CGImageSourceCreateImageAtIndex(source, 0, nil),
              strip.width > 0,
              strip.height >= frameCount,
              strip.height.isMultiple(of: frameCount) else {
            return nil
        }

        let frameHeight = strip.height / frameCount
        return (0..<frameCount).compactMap { index in
            guard let frame = strip.cropping(
                to: CGRect(
                    x: 0,
                    y: index * frameHeight,
                    width: strip.width,
                    height: frameHeight
                )
            ) else {
                return nil
            }
            return NSImage(
                cgImage: frame,
                size: NSSize(width: strip.width, height: frameHeight)
            )
        }
    }
}

@MainActor
private final class AnimationFramesBox: NSObject {
    let images: [NSImage]

    init(images: [NSImage]) {
        self.images = images
    }
}

@MainActor
private final class CursorImageCache {
    static let shared = CursorImageCache()

    private let imageCache = NSCache<NSString, NSImage>()
    private let animationCache = NSCache<NSString, AnimationFramesBox>()

    private init() {
        imageCache.countLimit = 64
        imageCache.totalCostLimit = 24 * 1_024 * 1_024
        animationCache.countLimit = 12
        animationCache.totalCostLimit = 48 * 1_024 * 1_024
    }

    func image(for url: URL) -> NSImage? {
        let file = fileIdentity(for: url)
        if let cached = imageCache.object(forKey: file.key) {
            return cached
        }

        guard let image = NSImage(contentsOf: url) else { return nil }
        imageCache.setObject(image, forKey: file.key, cost: max(file.size, 1))
        return image
    }

    func frames(for animation: CursorAssetAnimation) -> [NSImage]? {
        let file = fileIdentity(for: animation.stripURL)
        let key = NSString(
            string: "\(file.key)|frames:\(animation.frameCount)"
        )
        if let cached = animationCache.object(forKey: key) {
            return cached.images
        }

        guard let images = CursorAnimationFrameLoader.loadImages(
            at: animation.stripURL,
            frameCount: animation.frameCount
        ), images.count == animation.frameCount else {
            return nil
        }

        let cost = images.reduce(0) { partialResult, image in
            partialResult + max(
                Int(image.size.width * image.size.height * 4),
                1
            )
        }
        animationCache.setObject(
            AnimationFramesBox(images: images),
            forKey: key,
            cost: cost
        )
        return images
    }

    private func fileIdentity(for url: URL) -> (key: NSString, size: Int) {
        let modified = try? url.resourceValues(
            forKeys: [.contentModificationDateKey, .fileSizeKey]
        )
        return (
            NSString(
                string:
                    "\(url.path)|"
                    + "\(modified?.contentModificationDate?.timeIntervalSince1970 ?? 0)|"
                    + "\(modified?.fileSize ?? 0)"
            ),
            modified?.fileSize ?? 0
        )
    }
}
