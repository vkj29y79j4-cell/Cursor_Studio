import SwiftUI

struct MarketplaceView: View {
    @ObservedObject var appModel: AppViewModel
    @ObservedObject var model: MarketplaceViewModel
    @ObservedObject var preferences: AppPreferences
    @State private var showsAccount = false

    private let columns = [
        GridItem(.adaptive(minimum: 250, maximum: 340), spacing: 18),
    ]

    private var categories: [String] {
        [
            L10n.text("Minimal", "Минимализм"),
            L10n.text("Colorful", "Яркие"),
            L10n.text("Pixel Art", "Пиксель-арт"),
            L10n.text("Accessibility", "Универсальный доступ"),
            L10n.text("Professional", "Профессиональные"),
            L10n.text("Animated", "Анимированные"),
        ]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                categoryStrip

                if model.isLoading {
                    HStack {
                        Spacer()
                        ProgressView(L10n.marketplaceLoading)
                        Spacer()
                    }
                    .frame(minHeight: 300)
                } else if model.themes.isEmpty {
                    ContentUnavailableView {
                        Label(L10n.marketplaceEmptyTitle, systemImage: "magnifyingglass")
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
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
                        ForEach(model.themes) { theme in
                            MarketplaceThemeCard(
                                theme: theme,
                                isInstalling: model.installingThemeID == theme.id,
                                installProgress: model.installingThemeID == theme.id
                                    ? model.installProgress
                                    : nil,
                                onDetails: { model.openDetails(for: theme) },
                                onInstall: { model.install(theme) },
                                onCancel: model.cancelInstall
                            )
                        }
                    }
                }
            }
            .padding(28)
        }
        .navigationTitle(L10n.marketplace)
        .searchable(
            text: $model.query,
            placement: .toolbar,
            prompt: L10n.searchThemes
        )
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
            guard let installedThemeID = model.installedThemeID else { return }
            appModel.selectedThemeID = installedThemeID
            appModel.selectedSection = .library
            appModel.operationState = .success(L10n.installComplete)
            model.clearInstalledThemeID()
        }
        .task {
            model.load()
        }
        .sheet(item: $model.selectedTheme) { theme in
            MarketplaceThemeDetailView(
                theme: theme,
                details: model.details,
                isInstalling: model.installingThemeID == theme.id,
                installProgress: model.installingThemeID == theme.id
                    ? model.installProgress
                    : nil,
                onInstall: { model.install(theme) },
                onCancel: model.cancelInstall
            )
        }
        .sheet(
            isPresented: $showsAccount,
            onDismiss: {
                model.search(immediately: true)
            }
        ) {
            MarketplaceAccountView(
                appModel: appModel,
                model: appModel.marketplaceAccount,
                localThemes: appModel.store.themes,
                selectedThemeID: appModel.selectedThemeID
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
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: "storefront.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.tint)
                    .frame(width: 48, height: 48)
                    .background(
                        Color.accentColor.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 13)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n.marketplace)
                        .font(.largeTitle.bold())
                    Text(L10n.marketplaceSubtitle)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    showsAccount = true
                } label: {
                    Label(
                        appModel.marketplaceAccount.profile?.displayName
                            ?? (
                                appModel.marketplaceAccount.isSignedIn
                                    ? L10n.profile
                                    : L10n.signIn
                            ),
                        systemImage: appModel.marketplaceAccount.isModerator
                            ? "checkmark.shield.fill"
                            : "person.crop.circle"
                    )
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .help(L10n.creatorCenter)
            }

            HStack {
                catalogStatus

                if model.filters.verifiedOnly {
                    Label(L10n.verifiedOnly, systemImage: "checkmark.seal.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.blue)
                }

                Spacer()

                Text(L10n.sort)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker(
                    L10n.sort,
                    selection: $model.filters.sort
                ) {
                    ForEach(MarketplaceSort.allCases, id: \.rawValue) { sort in
                        Text(sort.displayName).tag(sort)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 280)
                .onChange(of: model.filters.sort) {
                    model.search(immediately: true)
                }
            }
        }
        .padding(20)
        .background(
            LinearGradient(
                colors: [
                    Color.accentColor.opacity(0.10),
                    Color.purple.opacity(0.05),
                    Color(nsColor: .controlBackgroundColor),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color(nsColor: .separatorColor))
        }
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

    private var categoryStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                categoryButton(
                    title: L10n.allCategories,
                    category: nil
                )
                ForEach(categories, id: \.self) { category in
                    categoryButton(title: category, category: category)
                }
            }
            .padding(.vertical, 1)
        }
    }

    private func categoryButton(
        title: String,
        category: String?
    ) -> some View {
        Button(title) {
            model.selectCategory(category)
        }
        .buttonStyle(
            MarketplaceCategoryButtonStyle(
                isSelected: model.filters.category == category
            )
        )
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
                Label(theme.creatorName, systemImage: "person.crop.circle")
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
                        .disabled(theme.compatibility == .incompatible)
                }
            }
        }
        .padding(14)
        .background(
            Color(nsColor: .controlBackgroundColor),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.045), radius: 8, y: 3)
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
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityHidden(true)
    }
}

private struct MarketplaceThemeDetailView: View {
    let theme: MarketplaceTheme
    let details: MarketplaceThemeDetails?
    let isInstalling: Bool
    let installProgress: Double?
    let onInstall: () -> Void
    let onCancel: () -> Void
    @Environment(\.dismiss) private var dismiss

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
                            Label(L10n.verified, systemImage: "checkmark.seal.fill")
                                .foregroundStyle(.blue)
                        }
                    }

                    Label(
                        theme.compatibility.displayName,
                        systemImage: theme.compatibility == .compatible
                            ? "checkmark.circle.fill"
                            : "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(
                        theme.compatibility == .compatible ? .green : .orange
                    )

                    if let details {
                        Text(details.description)
                            .foregroundStyle(.secondary)

                        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                            GridRow {
                                Text(L10n.creator).foregroundStyle(.secondary)
                                Text(theme.creatorName)
                            }
                            GridRow {
                                Text(L10n.category).foregroundStyle(.secondary)
                                Text(theme.category)
                            }
                            GridRow {
                                Text(L10n.version).foregroundStyle(.secondary)
                                Text(details.semanticVersion)
                            }
                        }

                        Text(L10n.includedCursors)
                            .font(.headline)
                        Text(details.includedRoles.joined(separator: " · "))
                            .foregroundStyle(.secondary)
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
        .frame(width: 600, height: 680)
    }
}

private struct MarketplaceCategoryButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                isSelected
                    ? Color.accentColor.opacity(configuration.isPressed ? 0.24 : 0.16)
                    : Color(nsColor: .controlBackgroundColor),
                in: Capsule()
            )
            .overlay {
                Capsule()
                    .stroke(
                        isSelected
                            ? Color.accentColor
                            : Color(nsColor: .separatorColor)
                    )
            }
    }
}
