import AppKit
import SwiftUI

struct CursorAssetView: View {
    let url: URL?
    var maximumSize: CGFloat = 72
    var fallbackSymbol = "cursorarrow"

    var body: some View {
        Group {
            if let url, let image = CursorImageCache.shared.image(for: url) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
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
}

@MainActor
private final class CursorImageCache {
    static let shared = CursorImageCache()

    private let cache = NSCache<NSString, NSImage>()

    private init() {
        cache.countLimit = 64
        cache.totalCostLimit = 24 * 1_024 * 1_024
    }

    func image(for url: URL) -> NSImage? {
        let modified = (
            try? url.resourceValues(
                forKeys: [.contentModificationDateKey, .fileSizeKey]
            )
        )
        let key = NSString(
            string: "\(url.path)|\(modified?.contentModificationDate?.timeIntervalSince1970 ?? 0)|\(modified?.fileSize ?? 0)"
        )
        if let cached = cache.object(forKey: key) {
            return cached
        }

        guard let image = NSImage(contentsOf: url) else { return nil }
        let cost = max(modified?.fileSize ?? 0, 1)
        cache.setObject(image, forKey: key, cost: cost)
        return image
    }
}
