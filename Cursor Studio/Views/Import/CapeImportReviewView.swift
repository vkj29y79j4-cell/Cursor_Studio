import SwiftUI

struct ThemeImportReviewView: View {
    let draft: ThemeImportDraft
    let onCancel: () -> Void
    let onImport: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(24)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    summary
                    recognizedRoles

                    if let metadata = draft.theme.importMetadata,
                       !metadata.unassignedEntries.isEmpty {
                        unassignedRoles(metadata.unassignedEntries)
                    }

                    if !draft.review.warningMessages.isEmpty {
                        warnings
                    }
                }
                .padding(24)
            }

            Divider()

            HStack {
                Button(L10n.cancel, role: .cancel, action: onCancel)
                Spacer()
                Button(L10n.importTheme, action: onImport)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 680, height: 650)
        .interactiveDismissDisabled()
    }

    private var header: some View {
        HStack(spacing: 14) {
            CursorAssetView(
                url: draft.theme.previewAssetFilename.map {
                    assetsDirectory.appending(path: $0)
                },
                maximumSize: 58,
                fallbackSymbol: "cursorarrow.rays"
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.reviewImportedTheme)
                    .font(.title2.weight(.semibold))
                Text(draft.theme.name)
                    .font(.headline)
                if let sourceFormat = draft.theme.importMetadata?.sourceFormat {
                    Text(sourceFormat)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let author = draft.theme.importMetadata?.author,
                   !author.isEmpty {
                    Text(L10n.byAuthor(author))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
    }

    private var summary: some View {
        LazyVGrid(
            columns: [
                GridItem(.adaptive(minimum: 110, maximum: 150), spacing: 10),
            ],
            spacing: 10
        ) {
            SummaryTile(
                value: draft.review.recognizedRoleCount,
                label: L10n.mapped,
                symbol: "checkmark.circle.fill",
                color: .green
            )
            SummaryTile(
                value: draft.review.unrecognizedRoleCount,
                label: L10n.unassigned,
                symbol: "questionmark.circle",
                color: .orange
            )
            SummaryTile(
                value: draft.review.missingImageCount,
                label: L10n.missing,
                symbol: "photo.badge.exclamationmark",
                color: .orange
            )
            SummaryTile(
                value: draft.review.animatedRoleCount,
                label: L10n.animated,
                symbol: "play.circle",
                color: .blue
            )
            SummaryTile(
                value: draft.review.warningMessages.count,
                label: L10n.warnings,
                symbol: "exclamationmark.triangle",
                color: .orange
            )
            if draft.review.staticAnimationFallbackCount > 0 {
                SummaryTile(
                    value: draft.review.staticAnimationFallbackCount,
                    label: L10n.staticFallback,
                    symbol: "pause.circle",
                    color: .orange
                )
            }
        }
    }

    private var recognizedRoles: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.mappedCursorRoles)
                .font(.headline)

            LazyVGrid(
                columns: [
                    GridItem(.adaptive(minimum: 185, maximum: 210), spacing: 10),
                ],
                alignment: .leading,
                spacing: 10
            ) {
                ForEach(draft.theme.entries.sorted {
                    $0.role.displayName < $1.role.displayName
                }) { entry in
                    HStack(spacing: 10) {
                        CursorAssetView(
                            url: assetsDirectory.appending(
                                path: entry.assetFilename
                            ),
                            maximumSize: 34,
                            fallbackSymbol: entry.role.symbolName
                        )

                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.role.displayName)
                                .font(.callout.weight(.medium))
                                .lineLimit(1)
                            Text(entry.sourceIdentifier ?? L10n.sourceCursor)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 0)

                        if entry.isAnimated {
                            Image(
                                systemName: entry.usesStaticAnimationFallback
                                    ? "pause.circle"
                                    : "play.circle.fill"
                            )
                            .foregroundStyle(
                                entry.usesStaticAnimationFallback
                                    ? .orange
                                    : .blue
                            )
                            .help(
                                entry.usesStaticAnimationFallback
                                    ? L10n.importedAsStaticFirstFrame
                                    : L10n.animationFramesHelp(entry.frameCount)
                            )
                        }
                    }
                    .padding(9)
                    .background(
                        Color(nsColor: .controlBackgroundColor),
                        in: RoundedRectangle(cornerRadius: 9)
                    )
                }
            }
        }
    }

    private func unassignedRoles(
        _ entries: [UnassignedCursorEntry]
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(L10n.unassignedSourceCursors, systemImage: "questionmark.circle")
                .font(.headline)

            Text(
                L10n.unassignedSourceDetail
            )
            .font(.callout)
            .foregroundStyle(.secondary)

            ForEach(entries) { entry in
                HStack {
                    Text(entry.sourceIdentifier)
                        .font(.callout.monospaced())
                    Spacer()
                    Text(entry.reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var warnings: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(L10n.importNotes, systemImage: "exclamationmark.triangle")
                .font(.headline)

            ForEach(
                Array(draft.review.warningMessages.enumerated()),
                id: \.offset
            ) { _, warning in
                Text("• \(warning)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }

    private var assetsDirectory: URL {
        draft.stagingThemeDirectory.appending(
            path: "Assets",
            directoryHint: .isDirectory
        )
    }
}

private struct SummaryTile: View {
    let value: Int
    let label: String
    let symbol: String
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 0) {
                Text(value.formatted())
                    .font(.headline.monospacedDigit())
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(11)
        .background(
            Color(nsColor: .controlBackgroundColor),
            in: RoundedRectangle(cornerRadius: 10)
        )
    }
}
