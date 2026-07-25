import AppKit
import SwiftUI

struct HotspotEditorView: View {
    let imageURL: URL
    let pixelWidth: Int
    let pixelHeight: Int
    @Binding var hotspot: CursorHotspot

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.hotspot)
                .font(.headline)

            GeometryReader { proxy in
                let imageSize = CGSize(
                    width: max(pixelWidth, 1),
                    height: max(pixelHeight, 1)
                )
                let frame = aspectFitFrame(
                    content: imageSize,
                    container: proxy.size
                )

                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(nsColor: .underPageBackgroundColor))

                    CheckerboardView()
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .frame(width: frame.width, height: frame.height)
                        .offset(x: frame.minX, y: frame.minY)

                    if let image = NSImage(contentsOf: imageURL) {
                        Image(nsImage: image)
                            .resizable()
                            .interpolation(.none)
                            .frame(width: frame.width, height: frame.height)
                            .offset(x: frame.minX, y: frame.minY)
                    }

                    hotspotMarker
                        .position(
                            x: frame.minX + CGFloat(hotspot.normalizedX) * frame.width,
                            y: frame.minY + CGFloat(hotspot.normalizedY) * frame.height
                        )
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onEnded { value in
                            let x = ((value.location.x - frame.minX) / frame.width)
                                .clamped(to: 0...1)
                            let y = ((value.location.y - frame.minY) / frame.height)
                                .clamped(to: 0...1)
                            hotspot = CursorHotspot(
                                normalizedX: x,
                                normalizedY: y
                            )
                        }
                )
                .accessibilityLabel(L10n.hotspotEditor)
                .accessibilityHint(L10n.hotspotEditorHint)
            }
            .frame(height: 260)

            let point = hotspot.pixelPoint(
                width: pixelWidth,
                height: pixelHeight
            )
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 6) {
                GridRow {
                    Text(L10n.position)
                        .foregroundStyle(.secondary)
                    Text("X \(Int(point.x.rounded()))  ·  Y \(Int(point.y.rounded()))")
                        .monospacedDigit()
                }
                GridRow {
                    Text(L10n.image)
                        .foregroundStyle(.secondary)
                    Text(L10n.pixelSize(width: pixelWidth, height: pixelHeight))
                        .monospacedDigit()
                }
            }
            .font(.callout)

            Divider()

            HStack(spacing: 14) {
                CursorAssetView(url: imageURL, maximumSize: 64)
                    .padding(8)
                    .background {
                        CheckerboardView(squareSize: 6)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n.approximateActualSize)
                        .font(.callout.weight(.medium))
                    Text(L10n.accessibilityScalingDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var hotspotMarker: some View {
        ZStack {
            Circle()
                .fill(.white)
                .frame(width: 18, height: 18)
            Circle()
                .stroke(.black, lineWidth: 2)
                .frame(width: 18, height: 18)
            Circle()
                .fill(.red)
                .frame(width: 6, height: 6)
        }
        .shadow(radius: 1)
        .accessibilityHidden(true)
    }

    private func aspectFitFrame(content: CGSize, container: CGSize) -> CGRect {
        let insetContainer = CGSize(
            width: max(container.width - 28, 1),
            height: max(container.height - 28, 1)
        )
        let scale = min(
            insetContainer.width / content.width,
            insetContainer.height / content.height
        )
        let size = CGSize(width: content.width * scale, height: content.height * scale)
        return CGRect(
            x: (container.width - size.width) / 2,
            y: (container.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
