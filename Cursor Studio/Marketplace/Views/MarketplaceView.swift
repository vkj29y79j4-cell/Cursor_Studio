import SwiftUI

struct MarketplaceView: View {
    @ObservedObject var appModel: AppViewModel
    @ObservedObject var model: MarketplaceViewModel
    @ObservedObject var preferences: AppPreferences
    let onShowAccount: () -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 250, maximum: 360), spacing: 16),
    ]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                header

                if model.isLoading {
                    HStack {
                        Spacer()
                        ProgressView(L10n.marketplaceLoading)
                        Spacer()
                    }
                    .frame(minHeight: 300)
                } else if model.themes.isEmpty {
                    ContentUnavailableView {
                        Label(
                            L10n.marketplaceEmptyTitle,
                            systemImage: "magnifyingglass"
                        )
                    } description: {
                        Text(
                            model.query.isEmpty && model.filters.category == nil
                                && !model.filters.verifiedOnly
                                ? L10n.marketplaceNoPublishedThemesDetail
                                : L10n.marketplaceEmptyDetail
                        )
                    } actions: {
                        if hasActiveFilters {
                            Button(L10n.clearFilters) {
                                clearFilters()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .frame(minHeight: 320)
                } else {
                    LazyVGrid(
                        columns: columns,
                        alignment: .leading,
                        spacing: 16
                    ) {
                        ForEach(model.themes) { theme in
                            MarketplaceThemeCard(
                                theme: theme,
                                isInstalling:
                                    model.installingThemeID == theme.id,
                                installProgress:
                                    model.installingThemeID == theme.id
                                    ? model.installProgress
                                    : nil,
                                onDetails: {
                                    model.openDetails(for: theme)
                                },
                                onInstall: {
                                    model.install(theme)
                                },
                                onCancel: model.cancelInstall
                            )
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle(L10n.marketplace)
        .onChange(of: model.query) {
            model.search()
        }
        .onChange(of: preferences.verifiedOnly) {
            model.updatePreferences(preferences)
        }
        .onChange(of: preferences.marketplaceContentLanguage) {
            model.updatePreferences(preferences)
        }
        .onChange(of: model.installedThemeID) {
            guard let installedThemeID = model.installedThemeID else {
                return
            }
            appModel.selectedThemeID = installedThemeID
            appModel.selectedSection = .library
            appModel.operationState = .success(L10n.installComplete)
            model.clearInstalledThemeID()
        }
        .task {
            model.load()
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    model.search(immediately: true)
                } label: {
                    Label(
                        L10n.refresh,
                        systemImage: "arrow.clockwise"
                    )
                }
                .help(L10n.refresh)

                Button(action: onShowAccount) {
                    Label(
                        appModel.marketplaceAccount.profile?.displayName
                            ?? (
                                appModel.marketplaceAccount.isSignedIn
                                    ? L10n.profile
                                    : L10n.creatorCenter
                            ),
                        systemImage:
                            appModel.marketplaceAccount.isModerator
                            ? "checkmark.shield.fill"
                            : "person.crop.circle"
                    )
                }
                .help(L10n.creatorCenter)
            }
        }
        .sheet(item: $model.selectedTheme) { theme in
            MarketplaceThemeDetailView(
                theme: theme,
                details: model.details,
                cursorPreviews: model.cursorPreviews,
                isLoadingCursorPreviews: model.isLoadingCursorPreviews,
                cursorPreviewMessage: model.cursorPreviewMessage,
                isInstalling: model.installingThemeID == theme.id,
                installProgress: model.installingThemeID == theme.id
                    ? model.installProgress
                    : nil,
                onInstall: { model.install(theme) },
                onCancel: model.cancelInstall
            )
        }
        .alert(
            L10n.installationFailed,
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.dismissError() } }
            )
        ) {
            Button(L10n.retry) {
                model.retryInstall()
            }
            Button(L10n.cancel, role: .cancel) {
                model.dismissError()
            }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(contentTitle)
                    .font(.title2.weight(.semibold))

                Text(
                    L10n.marketplaceThemeCount(
                        model.themes.count
                    )
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            }

            Spacer()

            catalogStatus
                .font(.caption)

            if model.filters.verifiedOnly {
                Label(
                    L10n.verifiedOnly,
                    systemImage: "checkmark.seal.fill"
                )
                .font(.caption)
                .foregroundStyle(.blue)
            }
        }
        .padding(.bottom, 2)
    }

    private var contentTitle: String {
        if !model.query.isEmpty {
            return L10n.searchResults
        }
        if let category = model.filters.category {
            return category
        }
        return model.filters.sort.displayName
    }

    @ViewBuilder
    private var catalogStatus: some View {
        if model.usesMockService {
            Label(L10n.previewCatalog, systemImage: "shippingbox")
                .foregroundStyle(.secondary)
        } else if model.isOffline {
            Label(L10n.cachedResults, systemImage: "wifi.slash")
                .foregroundStyle(.orange)
        } else {
            Label(L10n.liveCatalog, systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        }
    }

    private var hasActiveFilters: Bool {
        !model.query.isEmpty
            || model.filters.category != nil
            || model.filters.verifiedOnly
    }

    private func clearFilters() {
        model.query = ""
        model.filters.category = nil
        model.filters.verifiedOnly = false
        preferences.verifiedOnly = false
        model.search(immediately: true)
    }
}

private struct MarketplaceThemeCard: View {
    let theme: MarketplaceTheme
    let isInstalling: Bool
    let installProgress: Double?
    let onDetails: () -> Void
    let onInstall: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            Button(action: onDetails) {
                VStack(alignment: .leading, spacing: 13) {
                    MarketplacePreview(theme: theme)

                    HStack(alignment: .firstTextBaseline) {
                        Text(theme.title)
                            .font(.headline)
                            .lineLimit(1)
                        if theme.isVerified {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundStyle(.blue)
                                .help(L10n.verified)
                                .accessibilityLabel(L10n.verified)
                        }
                        Spacer()
                    }

                    Text(theme.summary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .frame(minHeight: 36, alignment: .topLeading)

                    HStack {
                        Label(
                            theme.compatibility.displayName,
                            systemImage: compatibilitySymbol
                        )
                        .foregroundStyle(compatibilityColor)
                        Spacer()
                        Text(L10n.downloadCount(theme.downloadCount))
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(L10n.viewDetails)

            Divider()

            HStack {
                Label(
                    theme.creatorName,
                    systemImage: "person.crop.circle"
                )
                .font(.caption.weight(.medium))
                .lineLimit(1)

                Spacer()

                Text(theme.category)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.quaternary, in: Capsule())

                if isInstalling {
                    ProgressView(value: installProgress)
                        .frame(width: 70)
                    Button(L10n.cancel, action: onCancel)
                        .controlSize(.small)
                } else {
                    Button(L10n.install, action: onInstall)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(
                            theme.compatibility == .incompatible
                        )
                }
            }
        }
        .padding(14)
        .background(
            Color(nsColor: .controlBackgroundColor),
            in: RoundedRectangle(
                cornerRadius: 10,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 10,
                style: .continuous
            )
            .stroke(
                Color(nsColor: .separatorColor),
                lineWidth: 1
            )
        }
    }

    private var compatibilitySymbol: String {
        switch theme.compatibility {
        case .compatible: "checkmark.circle.fill"
        case .limited: "exclamationmark.triangle.fill"
        case .incompatible: "xmark.octagon.fill"
        case .unknown: "questionmark.circle"
        }
    }

    private var compatibilityColor: Color {
        switch theme.compatibility {
        case .compatible: .green
        case .limited: .orange
        case .incompatible: .red
        case .unknown: .secondary
        }
    }
}

private struct MarketplacePreview: View {
    let theme: MarketplaceTheme

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.accentColor.opacity(0.24),
                    Color.purple.opacity(0.16),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            if let previewURL = theme.previewURL {
                AsyncImage(url: previewURL) { image in
                    image
                        .resizable()
                        .scaledToFit()
                        .padding(22)
                } placeholder: {
                    ProgressView()
                }
            } else {
                Image(systemName: "cursorarrow.rays")
                    .font(.system(size: 52, weight: .light))
                    .foregroundStyle(.tint)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 150)
        .clipShape(
            RoundedRectangle(
                cornerRadius: 10,
                style: .continuous
            )
        )
        .accessibilityHidden(true)
    }
}

private struct MarketplaceThemeDetailView: View {
    let theme: MarketplaceTheme
    let details: MarketplaceThemeDetails?
    let cursorPreviews: [MarketplaceCursorPreview]
    let isLoadingCursorPreviews: Bool
    let cursorPreviewMessage: String?
    let isInstalling: Bool
    let installProgress: Double?
    let onInstall: () -> Void
    let onCancel: () -> Void
    @Environment(\.dismiss) private var dismiss

    private let previewColumns = [
        GridItem(
            .adaptive(minimum: 128, maximum: 165),
            spacing: 12
        ),
    ]

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    MarketplacePreview(theme: theme)
                        .frame(height: 220)

                    HStack {
                        Text(theme.title)
                            .font(.title.bold())
                        if theme.isVerified {
                            Label(
                                L10n.verified,
                                systemImage: "checkmark.seal.fill"
                            )
                            .foregroundStyle(.blue)
                        }
                    }

                    Label(
                        theme.compatibility.displayName,
                        systemImage:
                            theme.compatibility == .compatible
                            ? "checkmark.circle.fill"
                            : "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(
                        theme.compatibility == .compatible
                            ? .green
                            : .orange
                    )

                    if let details {
                        Text(details.description)
                            .foregroundStyle(.secondary)

                        Grid(
                            alignment: .leading,
                            horizontalSpacing: 18,
                            verticalSpacing: 8
                        ) {
                            GridRow {
                                Text(L10n.creator)
                                    .foregroundStyle(.secondary)
                                Text(theme.creatorName)
                            }
                            GridRow {
                                Text(L10n.category)
                                    .foregroundStyle(.secondary)
                                Text(theme.category)
                            }
                            GridRow {
                                Text(L10n.version)
                                    .foregroundStyle(.secondary)
                                Text(details.semanticVersion)
                            }
                        }

                        Divider()

                        Text(L10n.cursorPackPreview)
                            .font(.headline)

                        if isLoadingCursorPreviews {
                            HStack(spacing: 10) {
                                ProgressView()
                                    .controlSize(.small)
                                Text(L10n.loadingCursorPreviews)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(
                                maxWidth: .infinity,
                                minHeight: 90,
                                alignment: .center
                            )
                        } else if !cursorPreviews.isEmpty {
                            LazyVGrid(
                                columns: previewColumns,
                                alignment: .leading,
                                spacing: 12
                            ) {
                                ForEach(cursorPreviews) { preview in
                                    MarketplaceCursorPreviewCard(
                                        preview: preview
                                    )
                                }
                            }
                        } else {
                            Label(
                                cursorPreviewMessage
                                    ?? L10n.cursorPreviewUnavailable,
                                systemImage:
                                    "exclamationmark.triangle"
                            )
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .frame(
                                maxWidth: .infinity,
                                alignment: .leading
                            )
                            .padding(12)
                            .background(
                                Color(nsColor: .controlBackgroundColor),
                                in: RoundedRectangle(cornerRadius: 10)
                            )

                            Text(L10n.includedCursors)
                                .font(.headline)
                            Text(
                                details.includedRoles.joined(
                                    separator: " · "
                                )
                            )
                            .foregroundStyle(.secondary)
                        }
                    } else {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(30)
                    }
                }
                .padding(24)
            }

            Divider()

            HStack {
                Button(L10n.done) {
                    dismiss()
                }
                Spacer()
                if isInstalling {
                    ProgressView(value: installProgress)
                        .frame(width: 120)
                    Button(L10n.cancel, action: onCancel)
                } else {
                    Button(L10n.install, action: onInstall)
                        .buttonStyle(.borderedProminent)
                        .disabled(
                            details == nil
                                || theme.compatibility == .incompatible
                        )
                }
            }
            .padding(16)
        }
        .frame(width: 740, height: 760)
    }
}

private struct MarketplaceCursorPreviewCard: View {
    let preview: MarketplaceCursorPreview

    private var animation: CursorAssetAnimation? {
        guard let animationStripURL = preview.animationStripURL else {
            return nil
        }
        return CursorAssetAnimation(
            stripURL: animationStripURL,
            frameCount: preview.frameCount,
            frameDuration: preview.frameDuration
        )
    }

    var body: some View {
        VStack(spacing: 9) {
            CursorAssetView(
                url: preview.assetURL,
                animation: animation,
                maximumSize: 66,
                fallbackSymbol: preview.role.symbolName
            )
            .frame(maxWidth: .infinity)
            .padding(.top, 10)

            VStack(spacing: 3) {
                Text(preview.role.displayName)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)

                Text(
                    L10n.pixelSize(
                        width: preview.pixelWidth,
                        height: preview.pixelHeight
                    )
                )
                .font(.caption2)
                .foregroundStyle(.secondary)

                if preview.frameCount > 1 {
                    Label(
                        L10n.frameCount(preview.frameCount),
                        systemImage:
                            preview.usesStaticAnimationFallback
                            ? "pause.circle"
                            : "play.circle.fill"
                    )
                    .font(.caption2)
                    .foregroundStyle(
                        preview.usesStaticAnimationFallback
                            ? .orange
                            : .blue
                    )
                } else {
                    Text(L10n.staticCursor)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(minHeight: 50, alignment: .top)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(
            Color(nsColor: .controlBackgroundColor),
            in: RoundedRectangle(
                cornerRadius: 12,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 12,
                style: .continuous
            )
            .stroke(Color(nsColor: .separatorColor))
        }
        .accessibilityElement(children: .combine)
    }
}
