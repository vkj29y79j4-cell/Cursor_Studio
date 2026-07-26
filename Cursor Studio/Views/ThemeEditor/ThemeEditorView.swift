import SwiftUI

struct ThemeEditorView: View {
    @ObservedObject var model: AppViewModel
    let theme: CursorTheme
    let onImport: () -> Void
    @FocusState private var isThemeNameFocused: Bool

    private let columns = [
        GridItem(.adaptive(minimum: 155, maximum: 220), spacing: 14),
    ]

    var body: some View {
        HStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header

                    LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                        ForEach(CursorRole.allCases) { role in
                            let entry = theme.entry(for: role)
                            CursorRoleCard(
                                role: role,
                                entry: entry,
                                assetURL: entry.flatMap {
                                    model.store.assetURL(for: $0, themeID: theme.id)
                                },
                                animation: entry.flatMap {
                                    CursorAssetAnimation.preview(
                                        for: $0,
                                        themeID: theme.id,
                                        paths: model.paths
                                    )
                                },
                                isSelected: model.selectedRole == role,
                                onSelect: {
                                    withAnimation(.easeOut(duration: 0.15)) {
                                        model.selectedRole = role
                                    }
                                },
                                onDrop: { url in
                                    model.importFile(from: url, for: role)
                                }
                            )
                        }
                    }
                }
                .padding(28)
            }
            .frame(minWidth: 520)

            Divider()

            CursorInspectorView(model: model, onImport: onImport)
        }
        .navigationTitle(theme.name)
        .onChange(of: model.themeNameFocusRequest) {
            isThemeNameFocused = true
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                TextField(
                    L10n.themeName,
                    text: Binding(
                        get: { model.selectedTheme?.name ?? theme.name },
                        set: { name in
                            model.renameSelectedTheme(to: name)
                        }
                    )
                )
                .textFieldStyle(.plain)
                .font(.largeTitle.weight(.bold))
                .focused($isThemeNameFocused)
                .accessibilityLabel(L10n.themeName)

                Spacer()

                if model.store.activeThemeID == theme.id {
                    Label(L10n.active, systemImage: "checkmark.circle.fill")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.green)
                }
            }

            HStack {
                Text(L10n.configureRolesDetail)
                    .foregroundStyle(.secondary)
                Spacer()
                OperationStatusView(state: model.operationState)
            }

            HStack(spacing: 8) {
                ThemeMetric(
                    title: L10n.cursorCount(
                        theme.entries.count,
                        total: CursorRole.allCases.count
                    ),
                    systemImage: "square.grid.2x2"
                )

                let animatedCount = theme.entries.filter(\.isAnimated).count
                if animatedCount > 0 {
                    ThemeMetric(
                        title: L10n.animatedCursorCount(animatedCount),
                        systemImage: "play.circle.fill",
                        color: .blue
                    )
                }

                let fallbackCount = theme.entries.filter(
                    \.usesStaticAnimationFallback
                ).count
                if fallbackCount > 0 {
                    ThemeMetric(
                        title: L10n.staticFallbackCount(fallbackCount),
                        systemImage: "pause.circle.fill",
                        color: .orange
                    )
                }
            }

            if let metadata = theme.importMetadata {
                HStack(spacing: 8) {
                    Label(metadata.sourceFormat, systemImage: "archivebox")
                    if let author = metadata.author, !author.isEmpty {
                        Text(L10n.byAuthor(author))
                    }
                    if !metadata.warnings.isEmpty {
                        Label(
                            metadata.warnings.count.formatted(),
                            systemImage: "exclamationmark.triangle"
                        )
                        .foregroundStyle(.orange)
                        .help(L10n.importNoteCount(metadata.warnings.count))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }
}

private struct ThemeMetric: View {
    let title: String
    let systemImage: String
    var color: Color = .secondary

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                color.opacity(0.09),
                in: Capsule(style: .continuous)
            )
    }
}
