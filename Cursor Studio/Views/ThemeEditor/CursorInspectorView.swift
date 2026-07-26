import SwiftUI

struct CursorInspectorView: View {
    @ObservedObject var model: AppViewModel
    let onImport: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Label(model.selectedRole.displayName, systemImage: model.selectedRole.symbolName)
                    .font(.title3.weight(.semibold))

                if let entry = model.selectedEntry,
                   let themeID = model.selectedThemeID,
                   let assetURL = model.store.assetURL(for: entry, themeID: themeID) {
                    HotspotEditorView(
                        imageURL: assetURL,
                        pixelWidth: entry.pixelWidth,
                        pixelHeight: entry.pixelHeight,
                        hotspot: Binding(
                            get: { model.selectedEntry?.hotspot ?? entry.hotspot },
                            set: { hotspot in
                                model.updateHotspot(hotspot)
                            }
                        )
                    )

                    Divider()

                    if entry.isAnimated {
                        HStack(spacing: 14) {
                            CursorAssetView(
                                url: assetURL,
                                animation: CursorAssetAnimation.preview(
                                    for: entry,
                                    themeID: themeID,
                                    paths: model.paths
                                ),
                                maximumSize: 72,
                                fallbackSymbol: model.selectedRole.symbolName
                            )
                            .padding(8)
                            .background(
                                Color(nsColor: .controlBackgroundColor),
                                in: RoundedRectangle(
                                    cornerRadius: 12,
                                    style: .continuous
                                )
                            )

                            VStack(alignment: .leading, spacing: 6) {
                                Text(L10n.livePreview)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)

                                Label(
                                    L10n.frameCount(entry.frameCount),
                                    systemImage: entry.usesStaticAnimationFallback
                                        ? "pause.circle"
                                        : "play.circle"
                                )
                                .font(.headline)

                                Text(
                                    entry.usesStaticAnimationFallback
                                        ? entry.animationFallbackReason
                                            ?? L10n.firstFrameUsed
                                        : L10n.frameDuration(
                                            entry.frameDuration.formatted(
                                                .number.precision(.fractionLength(0...3))
                                            )
                                        )
                                )
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            }
                        }

                        Divider()
                    }

                    HStack {
                        Button(L10n.replacePNG, action: onImport)
                        Spacer()
                        Button(L10n.remove, role: .destructive) {
                            model.removeSelectedCursor()
                        }
                    }
                } else {
                    ContentUnavailableView {
                        Label(L10n.noCursorImage, systemImage: "photo.badge.plus")
                    } description: {
                        Text(L10n.noCursorImageDetail)
                    } actions: {
                        Button(L10n.importPNG, action: onImport)
                            .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, minHeight: 340)
                }
            }
            .padding(22)
        }
        .frame(minWidth: 320, idealWidth: 350, maxWidth: 390)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
