import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppViewModel

    var body: some View {
        TabView {
            GeneralSettingsView(model: model, preferences: model.preferences)
                .tabItem {
                    Label(L10n.settingsGeneral, systemImage: "gear")
                }

            CursorSettingsView(model: model, preferences: model.preferences)
                .tabItem {
                    Label(L10n.settingsCursor, systemImage: "cursorarrow.rays")
                }

            MarketplaceSettingsView(
                model: model,
                preferences: model.preferences
            )
                .tabItem {
                    Label(L10n.settingsMarketplace, systemImage: "storefront")
                }

            PrivacyView(showsDoneButton: false)
                .tabItem {
                    Label(L10n.privacy, systemImage: "hand.raised")
                }

            AboutSettingsView(model: model)
                .tabItem {
                    Label(L10n.settingsAbout, systemImage: "info.circle")
                }
        }
        .frame(width: 660, height: 500)
    }
}

private struct GeneralSettingsView: View {
    @ObservedObject var model: AppViewModel
    @ObservedObject var preferences: AppPreferences
    @State private var settingError: String?
    @State private var isSettingErrorPresented = false

    var body: some View {
        Form {
            Section {
                Picker(L10n.language, selection: $preferences.language) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.displayName).tag(language)
                    }
                }

                if preferences.language != preferences.launchedLanguage {
                    Label(
                        L10n.languageRestartRequired,
                        systemImage: "arrow.clockwise"
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
            }

            Section {
                Toggle(
                    L10n.launchAtLogin,
                    isOn: Binding(
                        get: { preferences.launchAtLogin },
                        set: { enabled in
                            updateLaunchAtLogin(enabled)
                        }
                    )
                )
                Toggle(
                    L10n.keepCursorActive,
                    isOn: $preferences.keepCursorActiveWhenWindowClosed
                )
                .disabled(preferences.keepCursorActiveAfterAppQuit)

                Toggle(
                    L10n.keepCursorActiveAfterAppQuit,
                    isOn: $preferences.keepCursorActiveAfterAppQuit
                )

                if preferences.keepCursorActiveAfterAppQuit {
                    Text(L10n.keepCursorActiveAfterAppQuitDetail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Toggle(
                    L10n.confirmBeforeDeleting,
                    isOn: $preferences.confirmBeforeDeletingTheme
                )
            }

            Section {
                Button(L10n.showOnboarding) {
                    model.showOnboarding()
                }
            }
        }
        .formStyle(.grouped)
        .padding(.top, 8)
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
            settingError = L10n.settingError(error.localizedDescription)
            isSettingErrorPresented = true
        }
    }
}

private struct CursorSettingsView: View {
    @ObservedObject var model: AppViewModel
    @ObservedObject var preferences: AppPreferences

    var body: some View {
        Form {
            Section(L10n.activeTheme) {
                LabeledContent(
                    L10n.activeTheme,
                    value: model.store.activeTheme?.name ?? L10n.noActiveTheme
                )

                HStack {
                    Button(L10n.reapplyNow) {
                        Task { await model.applySelectedTheme() }
                    }
                    .disabled(model.selectedTheme?.entries.isEmpty != false)

                    Button(L10n.restoreNow) {
                        Task { await model.restoreSystemDefault() }
                    }
                }
            }

            Section(L10n.cursorCompatibilityTitle) {
                Toggle(
                    L10n.autoRecoverCursor,
                    isOn: $preferences.autoRecoverCursor
                )

                Label {
                    Text(ProductInfo.compatibilityNotice)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                .font(.callout)
            }

            Section {
                Button {
                    model.showDiagnosticLog()
                } label: {
                    Label(
                        L10n.showDiagnosticLog,
                        systemImage: "doc.text.magnifyingglass"
                    )
                }
            }
        }
        .formStyle(.grouped)
        .padding(.top, 8)
    }
}

private struct MarketplaceSettingsView: View {
    @ObservedObject var model: AppViewModel
    @ObservedObject var preferences: AppPreferences
    @State private var showsAccount = false

    var body: some View {
        Form {
            Section(L10n.marketplaceAccount) {
                LabeledContent(
                    L10n.marketplaceAccount,
                    value: model.marketplaceAccount.profile?.displayName
                        ?? model.marketplaceAccount.account?.email
                        ?? L10n.notSignedIn
                )

                Button(
                    model.marketplaceAccount.isSignedIn
                        ? L10n.openCreatorCenter
                        : L10n.signIn
                ) {
                    showsAccount = true
                }
                .disabled(!model.marketplaceAccount.backendConfigured)

                Text(L10n.marketplaceAccountOptional)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle(
                    L10n.automaticUpdates,
                    isOn: $preferences.marketplaceAutoUpdates
                )
                .disabled(true)

                Picker(
                    L10n.contentLanguage,
                    selection: $preferences.marketplaceContentLanguage
                ) {
                    ForEach(MarketplaceContentLanguage.allCases) { language in
                        Text(language.displayName).tag(language)
                    }
                }

                Toggle(
                    L10n.verifiedOnly,
                    isOn: $preferences.verifiedOnly
                )
            }
        }
        .formStyle(.grouped)
        .padding(.top, 8)
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
        VStack(spacing: 18) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 92, height: 92)
                .accessibilityHidden(true)

            VStack(spacing: 5) {
                Text(ProductInfo.name)
                    .font(.title.bold())
                Text("\(L10n.version) \(version) (\(L10n.build) \(build))")
                    .foregroundStyle(.secondary)
                Text(L10n.macOSRequirement)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button(L10n.website) {}
                    .disabled(true)
                Button(L10n.support) {}
                    .disabled(true)
                Button(L10n.licenses) {
                    showsLicenses = true
                }
            }

            Button {
                model.showDiagnosticLog()
            } label: {
                Label(
                    L10n.showDiagnosticLog,
                    systemImage: "doc.text.magnifyingglass"
                )
            }

            Spacer()
        }
        .padding(32)
        .sheet(isPresented: $showsLicenses) {
            VStack(alignment: .leading, spacing: 16) {
                Text(L10n.acknowledgements)
                    .font(.title2.bold())
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
