import SwiftUI

struct ThemeSidebarView: View {
    @ObservedObject var model: AppViewModel
    @ObservedObject var marketplaceModel: MarketplaceViewModel
    let libraryQuery: String
    let onShowMarketplaceAccount: () -> Void
    @State private var sidebarSelection: Selection?

    private enum Selection: Hashable {
        case library
        case marketplace
        case theme(UUID)
        case marketplaceSort(String)
        case marketplaceCategory(String)
    }

    private struct Category: Identifiable {
        let title: String
        let symbol: String

        var id: String { title }
    }

    private var categories: [Category] {
        [
            Category(
                title: L10n.text("Minimal", "Минимализм"),
                symbol: "circle.lefthalf.filled"
            ),
            Category(
                title: L10n.text("Colorful", "Яркие"),
                symbol: "paintpalette"
            ),
            Category(
                title: L10n.text("Pixel Art", "Пиксель-арт"),
                symbol: "square.grid.3x3"
            ),
            Category(
                title: L10n.text(
                    "Accessibility",
                    "Универсальный доступ"
                ),
                symbol: "accessibility"
            ),
            Category(
                title: L10n.text(
                    "Professional",
                    "Профессиональные"
                ),
                symbol: "briefcase"
            ),
            Category(
                title: L10n.text("Animated", "Анимированные"),
                symbol: "play.rectangle"
            ),
        ]
    }

    private var visibleThemes: [CursorTheme] {
        let query = libraryQuery.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !query.isEmpty else {
            return model.store.themes
        }
        return model.store.themes.filter {
            $0.name.localizedStandardContains(query)
        }
    }

    private var modelSelection: Selection {
        switch model.selectedSection {
        case .library:
            if let selectedThemeID = model.selectedThemeID {
                return .theme(selectedThemeID)
            }
            return .library
        case .marketplace:
            if let category = marketplaceModel.filters.category {
                return .marketplaceCategory(category)
            }
            return .marketplaceSort(
                marketplaceModel.filters.sort.rawValue
            )
        }
    }

    private func applySelection(_ selection: Selection) {
        switch selection {
        case .library:
            model.selectedSection = .library
        case .marketplace:
            model.selectedSection = .marketplace
        case .theme(let themeID):
            model.selectedThemeID = themeID
            model.selectedSection = .library
        case .marketplaceSort(let rawValue):
            guard let sort = MarketplaceSort(rawValue: rawValue) else {
                return
            }
            model.selectedSection = .marketplace
            marketplaceModel.filters.category = nil
            marketplaceModel.selectSort(sort)
        case .marketplaceCategory(let category):
            model.selectedSection = .marketplace
            marketplaceModel.selectCategory(category)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $sidebarSelection) {
                Section {
                    Label(
                        L10n.library,
                        systemImage: "square.grid.2x2"
                    )
                    .tag(Selection.library)

                    Label(
                        L10n.marketplace,
                        systemImage: "storefront"
                    )
                    .tag(Selection.marketplace)
                }

                if model.selectedSection == .library {
                    Section(L10n.themes) {
                        ForEach(visibleThemes) { theme in
                            ThemeSidebarRow(
                                theme: theme,
                                previewURL: model.store.previewURL(
                                    for: theme
                                ),
                                isActive:
                                    model.store.activeThemeID == theme.id
                            )
                            .tag(Selection.theme(theme.id))
                            .contextMenu {
                                Button(L10n.duplicate) {
                                    model.selectedThemeID = theme.id
                                    model.duplicateSelectedTheme()
                                }
                                Button(L10n.exportTheme) {
                                    model.selectedThemeID = theme.id
                                    model.exportSelectedTheme()
                                }
                                .disabled(theme.entries.isEmpty)
                                Divider()
                                Button(
                                    L10n.delete,
                                    role: .destructive
                                ) {
                                    model.selectedThemeID = theme.id
                                    model.requestDeleteSelectedTheme()
                                }
                            }
                        }

                        if visibleThemes.isEmpty {
                            Text(L10n.noMatchingThemes)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Section(L10n.discover) {
                        ForEach(
                            MarketplaceSort.allCases,
                            id: \.rawValue
                        ) { sort in
                            Label(
                                sort.displayName,
                                systemImage: symbol(for: sort)
                            )
                            .tag(
                                Selection.marketplaceSort(
                                    sort.rawValue
                                )
                            )
                        }
                    }

                    Section(L10n.category) {
                        ForEach(categories) { category in
                            Label(
                                category.title,
                                systemImage: category.symbol
                            )
                            .tag(
                                Selection.marketplaceCategory(
                                    category.title
                                )
                            )
                        }
                    }

                    Section {
                        Button(action: onShowMarketplaceAccount) {
                            Label(
                                model.marketplaceAccount.profile?
                                    .displayName
                                    ?? (
                                        model.marketplaceAccount
                                            .isSignedIn
                                            ? L10n.profile
                                            : L10n.creatorCenter
                                    ),
                                systemImage:
                                    model.marketplaceAccount.isModerator
                                    ? "checkmark.shield.fill"
                                    : "person.crop.circle"
                            )
                            .frame(
                                maxWidth: .infinity,
                                alignment: .leading
                            )
                        }
                        .buttonStyle(.plain)
                        .help(L10n.creatorCenter)
                    }
                }
            }
            .listStyle(.sidebar)
            .onAppear {
                sidebarSelection = modelSelection
            }
            .onChange(of: sidebarSelection) { _, newSelection in
                guard let newSelection,
                      newSelection != modelSelection else {
                    return
                }
                // A List can write its selection while SwiftUI is updating
                // the view hierarchy. Yield before publishing navigation
                // changes through the observable view models.
                Task { @MainActor in
                    await Task.yield()
                    guard sidebarSelection == newSelection else {
                        return
                    }
                    applySelection(newSelection)
                }
            }
            .onChange(of: modelSelection) { _, newSelection in
                guard sidebarSelection != newSelection else {
                    return
                }
                sidebarSelection = newSelection
            }

            Divider()

            HStack(spacing: 12) {
                if model.selectedSection == .library {
                    Button {
                        model.createTheme()
                    } label: {
                        Label(L10n.addTheme, systemImage: "plus")
                    }
                    .buttonStyle(.borderless)
                    .keyboardShortcut("n", modifiers: .command)
                }

                Spacer()

                SettingsLink {
                    Image(systemName: "gearshape")
                        .frame(width: 18, height: 18)
                }
                .labelsHidden()
                .buttonStyle(.borderless)
                .help(L10n.settings)
                .accessibilityLabel(L10n.settings)
            }
            .font(.callout)
            .padding(.horizontal, 12)
            .frame(height: 40)
        }
        .navigationTitle(ProductInfo.name)
        .navigationSplitViewColumnWidth(
            min: 220,
            ideal: 250,
            max: 320
        )
    }

    private func symbol(for sort: MarketplaceSort) -> String {
        switch sort {
        case .featured: "sparkles"
        case .recent: "clock"
        case .popular: "chart.line.uptrend.xyaxis"
        }
    }
}

private struct ThemeSidebarRow: View {
    let theme: CursorTheme
    let previewURL: URL?
    let isActive: Bool

    var body: some View {
        HStack(spacing: 10) {
            CursorAssetView(
                url: previewURL,
                maximumSize: 30,
                fallbackSymbol: "cursorarrow.rays"
            )
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(theme.name)
                    .lineLimit(1)

                HStack(spacing: 5) {
                    Text(
                        L10n.cursorCount(
                            theme.entries.count,
                            total: CursorRole.allCases.count
                        )
                    )
                    let animatedCount = theme.entries.filter(
                        \.isAnimated
                    ).count
                    if animatedCount > 0 {
                        Image(systemName: "play.circle.fill")
                            .foregroundStyle(.blue)
                            .help(
                                L10n.animatedCursorCount(
                                    animatedCount
                                )
                            )
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            if isActive {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .help(L10n.activeThemeHelp)
                    .accessibilityLabel(L10n.active)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}
