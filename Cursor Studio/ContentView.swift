import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var model: AppViewModel
    @StateObject private var marketplaceModel: MarketplaceViewModel
    @State private var isImporterPresented = false
    @State private var isMarketplaceAccountPresented = false
    @State private var libraryQuery = ""
    @State private var hasLoaded = false

    init(model: AppViewModel) {
        self.model = model
        _marketplaceModel = StateObject(
            wrappedValue: MarketplaceViewModel(
                store: model.store,
                paths: model.paths,
                preferences: model.preferences
            )
        )
    }

    var body: some View {
        NavigationSplitView {
            ThemeSidebarView(
                model: model,
                marketplaceModel: marketplaceModel,
                libraryQuery: libraryQuery,
                onShowMarketplaceAccount: {
                    isMarketplaceAccountPresented = true
                }
            )
        } detail: {
            switch model.selectedSection {
            case .library:
                if let theme = model.selectedTheme {
                    ThemeEditorView(
                        model: model,
                        theme: theme,
                        onImport: { isImporterPresented = true }
                    )
                } else {
                    ContentUnavailableView {
                        Label(L10n.noThemeSelected, systemImage: "cursorarrow.rays")
                    } description: {
                        Text(L10n.noThemeSelectedDetail)
                    } actions: {
                        Button(L10n.createTheme) {
                            model.createTheme()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            case .marketplace:
                MarketplaceView(
                    appModel: model,
                    model: marketplaceModel,
                    preferences: model.preferences,
                    onShowAccount: {
                        isMarketplaceAccountPresented = true
                    }
                )
            }
        }
        .frame(minWidth: 1_020, minHeight: 680)
        .navigationSplitViewStyle(.balanced)
        .searchable(
            text: activeSearchText,
            placement: .toolbar,
            prompt: model.selectedSection == .library
                ? L10n.searchLibrary
                : L10n.searchThemes
        )
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if model.selectedSection == .library {
                    Button {
                        isImporterPresented = true
                    } label: {
                        Label(L10n.importAction, systemImage: "square.and.arrow.down")
                    }
                    .help(L10n.importHelp)
                    .disabled(model.isPreparingThemeImport)

                    Button {
                        model.exportSelectedTheme()
                    } label: {
                        Label(
                            L10n.exportTheme,
                            systemImage: "square.and.arrow.up"
                        )
                    }
                    .help(L10n.exportThemeHelp)
                    .disabled(
                        model.selectedTheme?.entries.isEmpty != false
                            || model.isExportingTheme
                    )

                    Button {
                        Task { await model.applySelectedTheme() }
                    } label: {
                        Label(L10n.apply, systemImage: "cursorarrow.rays")
                    }
                    .buttonStyle(.borderedProminent)
                    .help(L10n.applyHelp)
                    .disabled(model.selectedTheme?.entries.isEmpty != false)

                    Button {
                        model.duplicateSelectedTheme()
                    } label: {
                        Label(L10n.duplicate, systemImage: "plus.square.on.square")
                    }
                    .help(L10n.duplicateHelp)
                    .disabled(model.selectedThemeID == nil)

                    Button {
                        Task { await model.restoreSystemDefault() }
                    } label: {
                        Label(
                            L10n.restoreMacOSCursor,
                            systemImage: "arrow.counterclockwise"
                        )
                    }
                    .help(L10n.restoreHelp)
                }
            }
        }
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [
                .cursorStudioThemePackage,
                .png,
                .svg,
                .mousecapeTheme,
                .windowsCursor,
                .windowsAnimatedCursor,
                .zipArchive,
                .folder,
            ],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    model.importFile(from: url)
                }
            case .failure(let error):
                model.presentedError = PresentedError(
                    title: L10n.importFailed,
                    message: error.localizedDescription
                )
            }
        }
        .onChange(of: model.importRequest) {
            isImporterPresented = true
        }
        .confirmationDialog(
            L10n.deleteThemeQuestion,
            isPresented: $model.isDeleteConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button(L10n.deleteTheme, role: .destructive) {
                Task { await model.deleteSelectedTheme() }
            }
            Button(L10n.cancel, role: .cancel) {}
        } message: {
            Text(L10n.deleteThemeDetail)
        }
        .sheet(isPresented: $model.isPrivacyPresented) {
            PrivacyView()
        }
        .sheet(
            isPresented: $isMarketplaceAccountPresented,
            onDismiss: {
                marketplaceModel.search(immediately: true)
            }
        ) {
            MarketplaceAccountView(
                appModel: model,
                model: model.marketplaceAccount,
                localThemes: model.store.themes,
                selectedThemeID: model.selectedThemeID
            )
        }
        .sheet(item: $model.themeImportDraft) { draft in
            ThemeImportReviewView(
                draft: draft,
                onCancel: model.cancelThemeImport,
                onImport: model.commitThemeImport
            )
        }
        .sheet(isPresented: $model.isOnboardingPresented) {
            OnboardingView(onComplete: model.completeOnboarding)
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            model.importFile(from: url)
            return true
        }
        .alert(item: $model.presentedError) { error in
            Alert(
                title: Text(error.title),
                message: Text(error.message),
                dismissButton: .default(Text(L10n.ok))
            )
        }
        .task {
            guard !hasLoaded else { return }
            hasLoaded = true
            MenuLocalization.apply()
            await model.load()
        }
        .onDisappear {
            model.mainWindowDidClose()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSApplication.willTerminateNotification
            )
        ) { _ in
            model.prepareForApplicationTermination()
        }
    }

    private var activeSearchText: Binding<String> {
        Binding {
            model.selectedSection == .library
                ? libraryQuery
                : marketplaceModel.query
        } set: { value in
            if model.selectedSection == .library {
                libraryQuery = value
            } else {
                marketplaceModel.query = value
            }
        }
    }
}

private extension UTType {
    static let cursorStudioThemePackage =
        UTType(
            filenameExtension:
                CursorStudioThemeArchiveService.pathExtension
        ) ?? .data
    static let mousecapeTheme =
        UTType(filenameExtension: "cape") ?? .propertyList
    static let windowsCursor =
        UTType(filenameExtension: "cur") ?? .data
    static let windowsAnimatedCursor =
        UTType(filenameExtension: "ani") ?? .data
    static let zipArchive =
        UTType(filenameExtension: "zip") ?? .archive
}
