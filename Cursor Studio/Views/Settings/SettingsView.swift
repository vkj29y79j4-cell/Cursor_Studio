import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppViewModel
    @State private var selection: SettingsDestination = .general

    var body: some View {
        NavigationSplitView {
            List(
                SettingsDestination.allCases,
                selection: $selection
            ) { destination in
                Label(
                    destination.title,
                    systemImage: destination.symbol
                )
                .tag(destination)
            }
            .listStyle(.sidebar)
            .navigationTitle(L10n.settings)
            .navigationSplitViewColumnWidth(
                min: 180,
                ideal: 195,
                max: 220
            )
        } detail: {
            detail
                .navigationTitle(selection.title)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(width: 820, height: 580)
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .general:
            GeneralSettingsView(
                model: model,
                preferences: model.preferences
            )
        case .cursor:
            CursorSettingsView(
                model: model,
                preferences: model.preferences
            )
        case .marketplace:
            MarketplaceSettingsView(
                model: model,
                preferences: model.preferences
            )
        case .privacy:
            PrivacySettingsView()
        case .about:
            AboutSettingsView(model: model)
        }
    }
}

private enum SettingsDestination:
    String,
    CaseIterable,
    Identifiable
{
    case general
    case cursor
    case marketplace
    case privacy
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: L10n.settingsGeneral
        case .cursor: L10n.settingsCursor
        case .marketplace: L10n.settingsMarketplace
        case .privacy: L10n.privacy
        case .about: L10n.settingsAbout
        }
    }

    var symbol: String {
        switch self {
        case .general: "gear"
        case .cursor: "cursorarrow.rays"
        case .marketplace: "storefront"
        case .privacy: "hand.raised"
        case .about: "info.circle"
        }
    }
}

private struct GeneralSettingsView: View {
    @ObservedObject var model: AppViewModel
    @ObservedObject var preferences: AppPreferences
    @State private var settingError: String?
    @State private var isSettingErrorPresented = false

    var body: some View {
        SettingsPane(
            title: L10n.settingsGeneral,
            subtitle: L10n.text(
                "Language, startup, and everyday behavior.",
                "Язык, запуск и повседневное поведение."
            )
        ) {
            SettingsGroup(
                title: L10n.text("Language & Region", "Язык и регион")
            ) {
                SettingsRow(
                    symbol: "globe",
                    title: L10n.language,
                    detail: L10n.text(
                        "Choose the language used throughout Cursor Studio.",
                        "Выберите язык интерфейса Cursor Studio."
                    )
                ) {
                    Picker(
                        L10n.language,
                        selection: $preferences.language
                    ) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(language.displayName).tag(language)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 165)
                }
            }

            if preferences.language != preferences.launchedLanguage {
                SettingsNotice(
                    symbol: "arrow.clockwise",
                    text: L10n.languageRestartRequired,
                    color: .orange
                )
            }

            SettingsGroup(
                title: L10n.text(
                    "Startup & Behavior",
                    "Запуск и поведение"
                )
            ) {
                SettingsRow(
                    symbol: "power",
                    title: L10n.launchAtLogin,
                    detail: L10n.text(
                        "Open Cursor Studio automatically after signing in to your Mac.",
                        "Автоматически открывать Cursor Studio после входа в macOS."
                    )
                ) {
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { preferences.launchAtLogin },
                            set: { enabled in
                                updateLaunchAtLogin(enabled)
                            }
                        )
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                }

                SettingsDivider()

                SettingsRow(
                    symbol: "macwindow",
                    title: L10n.keepCursorActive,
                    detail: L10n.text(
                        "Closing the main window will not restore the system cursor.",
                        "Закрытие главного окна не вернёт системный курсор."
                    )
                ) {
                    Toggle(
                        "",
                        isOn:
                            $preferences.keepCursorActiveWhenWindowClosed
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(
                        preferences.keepCursorActiveAfterAppQuit
                    )
                }

                SettingsDivider()

                SettingsRow(
                    symbol: "cursorarrow.motionlines",
                    title: L10n.keepCursorActiveAfterAppQuit,
                    detail: L10n.keepCursorActiveAfterAppQuitDetail
                ) {
                    Toggle(
                        "",
                        isOn:
                            $preferences.keepCursorActiveAfterAppQuit
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                }

                SettingsDivider()

                SettingsRow(
                    symbol: "trash",
                    title: L10n.confirmBeforeDeleting,
                    detail: L10n.text(
                        "Ask before a theme and its local assets are removed.",
                        "Спрашивать перед удалением темы и её локальных файлов."
                    )
                ) {
                    Toggle(
                        "",
                        isOn:
                            $preferences.confirmBeforeDeletingTheme
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                }
            }

            SettingsGroup(title: L10n.text("Help", "Помощь")) {
                SettingsRow(
                    symbol: "sparkles",
                    title: L10n.showOnboarding,
                    detail: L10n.text(
                        "Review importing, editing, and restoring cursors.",
                        "Повторите импорт, редактирование и восстановление курсоров."
                    )
                ) {
                    Button(L10n.text("Open", "Открыть")) {
                        model.showOnboarding()
                    }
                }
            }
        }
        .alert(
            L10n.preferenceFailed,
            isPresented: $isSettingErrorPresented
        ) {
            Button(L10n.ok) { settingError = nil }
        } message: {
            Text(settingError ?? "")
        }
    }

    private func updateLaunchAtLogin(_ enabled: Bool) {
        do {
            try preferences.setLaunchAtLogin(enabled)
        } catch {
            settingError = L10n.settingError(
                error.localizedDescription
            )
            isSettingErrorPresented = true
        }
    }
}

private struct CursorSettingsView: View {
    @ObservedObject var model: AppViewModel
    @ObservedObject var preferences: AppPreferences

    var body: some View {
        SettingsPane(
            title: L10n.settingsCursor,
            subtitle: L10n.text(
                "Control the active theme, recovery, and diagnostics.",
                "Управляйте активной темой, восстановлением и диагностикой."
            )
        ) {
            SettingsGroup(title: L10n.activeTheme) {
                SettingsRow(
                    symbol: "cursorarrow.rays",
                    title:
                        model.store.activeTheme?.name
                        ?? L10n.noActiveTheme,
                    detail:
                        model.store.activeTheme == nil
                        ? L10n.text(
                            "macOS is currently using the system cursor.",
                            "Сейчас macOS использует системный курсор."
                        )
                        : L10n.text(
                            "This theme is currently applied.",
                            "Эта тема сейчас применена."
                        ),
                    color:
                        model.store.activeTheme == nil
                        ? .secondary
                        : .green
                ) {
                    HStack {
                        Button(L10n.reapplyNow) {
                            Task {
                                await model.applySelectedTheme()
                            }
                        }
                        .disabled(
                            model.selectedTheme?.entries.isEmpty
                                != false
                        )

                        Button(L10n.restoreNow) {
                            Task {
                                await model.restoreSystemDefault()
                            }
                        }
                    }
                }
            }

            SettingsGroup(
                title: L10n.cursorCompatibilityTitle
            ) {
                SettingsRow(
                    symbol: "display",
                    title: L10n.autoRecoverCursor,
                    detail: L10n.text(
                        "Reapply the active theme when macOS replaces it after sleep or display changes.",
                        "Повторно применять тему, если macOS заменит её после сна или изменения дисплея."
                    )
                ) {
                    Toggle(
                        "",
                        isOn: $preferences.autoRecoverCursor
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                }
            }

            SettingsNotice(
                symbol: "exclamationmark.triangle.fill",
                text: ProductInfo.compatibilityNotice,
                color: .orange
            )

            SettingsGroup(
                title: L10n.text("Diagnostics", "Диагностика")
            ) {
                SettingsRow(
                    symbol: "doc.text.magnifyingglass",
                    title: L10n.showDiagnosticLog,
                    detail: L10n.text(
                        "Open the local log used to troubleshoot cursor application.",
                        "Открыть локальный журнал для диагностики применения курсора."
                    )
                ) {
                    Button(L10n.text("Show", "Показать")) {
                        model.showDiagnosticLog()
                    }
                }
            }
        }
    }
}

private struct MarketplaceSettingsView: View {
    @ObservedObject var model: AppViewModel
    @ObservedObject var preferences: AppPreferences
    @State private var showsAccount = false

    private var accountName: String {
        model.marketplaceAccount.profile?.displayName
            ?? model.marketplaceAccount.account?.email
            ?? L10n.notSignedIn
    }

    var body: some View {
        SettingsPane(
            title: L10n.settingsMarketplace,
            subtitle: L10n.text(
                "Account, catalog language, and trusted themes.",
                "Учётная запись, язык каталога и проверенные темы."
            )
        ) {
            SettingsGroup(title: L10n.marketplaceAccount) {
                SettingsRow(
                    symbol:
                        model.marketplaceAccount.isModerator
                        ? "checkmark.shield.fill"
                        : "person.crop.circle",
                    title: accountName,
                    detail: L10n.marketplaceAccountOptional,
                    color:
                        model.marketplaceAccount.isSignedIn
                        ? .green
                        : .secondary
                ) {
                    Button(
                        model.marketplaceAccount.isSignedIn
                            ? L10n.openCreatorCenter
                            : L10n.signIn
                    ) {
                        showsAccount = true
                    }
                    .disabled(
                        !model.marketplaceAccount.backendConfigured
                    )
                }
            }

            SettingsGroup(
                title: L10n.text(
                    "Catalog Preferences",
                    "Настройки каталога"
                )
            ) {
                SettingsRow(
                    symbol: "character.bubble",
                    title: L10n.contentLanguage,
                    detail: L10n.text(
                        "Choose which localized titles and descriptions to prefer.",
                        "Выберите предпочитаемый язык названий и описаний."
                    )
                ) {
                    Picker(
                        L10n.contentLanguage,
                        selection:
                            $preferences.marketplaceContentLanguage
                    ) {
                        ForEach(
                            MarketplaceContentLanguage.allCases
                        ) { language in
                            Text(language.displayName).tag(language)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 165)
                }

                SettingsDivider()

                SettingsRow(
                    symbol: "checkmark.seal",
                    title: L10n.verifiedOnly,
                    detail: L10n.text(
                        "Hide community themes that have not been verified.",
                        "Скрывать темы сообщества, которые ещё не проверены."
                    )
                ) {
                    Toggle(
                        "",
                        isOn: $preferences.verifiedOnly
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                }

                SettingsDivider()

                SettingsRow(
                    symbol: "arrow.triangle.2.circlepath",
                    title: L10n.automaticUpdates,
                    detail: L10n.text(
                        "Automatic theme updates are planned for a future release.",
                        "Автоматическое обновление тем появится в будущей версии."
                    ),
                    color: .secondary
                ) {
                    Toggle(
                        "",
                        isOn: $preferences.marketplaceAutoUpdates
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(true)
                }
            }
        }
        .sheet(isPresented: $showsAccount) {
            MarketplaceAccountView(
                appModel: model,
                model: model.marketplaceAccount,
                localThemes: model.store.themes,
                selectedThemeID: model.selectedThemeID
            )
        }
    }
}

private struct PrivacySettingsView: View {
    var body: some View {
        SettingsPane(
            title: L10n.privacy,
            subtitle: L10n.privacySummary
        ) {
            SettingsGroup(
                title: L10n.text(
                    "Your Data",
                    "Ваши данные"
                )
            ) {
                SettingsRow(
                    symbol: "macbook",
                    title: L10n.everythingStaysLocal,
                    detail: L10n.noImagesLeaveMac,
                    color: .green
                ) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }

                SettingsDivider()

                SettingsRow(
                    symbol: "chart.bar.xaxis",
                    title: L10n.noAnalytics,
                    detail: L10n.noAnalyticsDetail,
                    color: .green
                ) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }

                SettingsDivider()

                SettingsRow(
                    symbol: "person.crop.circle.badge.xmark",
                    title: L10n.noAccount,
                    detail: L10n.noAccountDetail,
                    color: .green
                ) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }

            SettingsNotice(
                symbol: "exclamationmark.triangle.fill",
                text: ProductInfo.compatibilityNotice,
                color: .orange
            )
        }
    }
}

private struct AboutSettingsView: View {
    @ObservedObject var model: AppViewModel
    @State private var showsLicenses = false

    private var version: String {
        Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "1.0"
    }

    private var build: String {
        Bundle.main.object(
            forInfoDictionaryKey: "CFBundleVersion"
        ) as? String ?? "1"
    }

    var body: some View {
        SettingsPane(
            title: L10n.settingsAbout,
            subtitle: L10n.macOSRequirement
        ) {
            VStack(spacing: 12) {
                Image(
                    nsImage:
                        NSApplication.shared.applicationIconImage
                )
                .resizable()
                .frame(width: 96, height: 96)
                .accessibilityHidden(true)

                Text(ProductInfo.name)
                    .font(.title.weight(.semibold))

                Text(
                    "\(L10n.version) \(version) · "
                        + "\(L10n.build) \(build)"
                )
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)

            SettingsGroup(
                title: L10n.text(
                    "Application",
                    "Приложение"
                )
            ) {
                SettingsRow(
                    symbol: "doc.text",
                    title: L10n.licenses,
                    detail: L10n.noThirdPartyLibraries
                ) {
                    Button(L10n.text("View", "Открыть")) {
                        showsLicenses = true
                    }
                }

                SettingsDivider()

                SettingsRow(
                    symbol: "doc.text.magnifyingglass",
                    title: L10n.showDiagnosticLog,
                    detail: L10n.text(
                        "Open Cursor Studio's local diagnostic log.",
                        "Открыть локальный журнал диагностики Cursor Studio."
                    )
                ) {
                    Button(L10n.text("Show", "Показать")) {
                        model.showDiagnosticLog()
                    }
                }
            }
        }
        .sheet(isPresented: $showsLicenses) {
            VStack(alignment: .leading, spacing: 16) {
                Text(L10n.acknowledgements)
                    .font(.title2.weight(.semibold))
                Text(L10n.noThirdPartyLibraries)
                    .foregroundStyle(.secondary)
                Spacer()
                HStack {
                    Spacer()
                    Button(L10n.done) {
                        showsLicenses = false
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(24)
            .frame(width: 480, height: 280)
        }
    }
}

private struct SettingsPane: View {
    let title: String
    let subtitle: String
    let content: AnyView

    init<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.content = AnyView(content())
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.largeTitle.weight(.semibold))
                    Text(subtitle)
                        .foregroundStyle(.secondary)
                }

                content
            }
            .padding(28)
            .frame(
                maxWidth: 680,
                alignment: .topLeading
            )
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct SettingsGroup: View {
    let title: String
    let content: AnyView

    init<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.content = AnyView(content())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            GroupBox {
                VStack(spacing: 0) {
                    content
                }
                .padding(.horizontal, 4)
            }
        }
    }
}

private struct SettingsRow: View {
    let symbol: String
    let title: String
    let detail: String
    let color: Color
    let trailing: AnyView

    init<Trailing: View>(
        symbol: String,
        title: String,
        detail: String,
        color: Color = .accentColor,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.symbol = symbol
        self.title = title
        self.detail = detail
        self.color = color
        self.trailing = AnyView(trailing())
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 28, height: 28)
                .background(
                    color.opacity(0.12),
                    in: RoundedRectangle(
                        cornerRadius: 7,
                        style: .continuous
                    )
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .fontWeight(.medium)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(
                        horizontal: false,
                        vertical: true
                    )
            }

            Spacer(minLength: 16)

            trailing
                .fixedSize()
        }
        .padding(.vertical, 10)
    }
}

private struct SettingsDivider: View {
    var body: some View {
        Divider()
            .padding(.leading, 40)
    }
}

private struct SettingsNotice: View {
    let symbol: String
    let text: String
    let color: Color

    var body: some View {
        Label {
            Text(text)
                .foregroundStyle(.secondary)
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(color)
        }
        .font(.callout)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            color.opacity(0.08),
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
            .stroke(color.opacity(0.20))
        }
    }
}
