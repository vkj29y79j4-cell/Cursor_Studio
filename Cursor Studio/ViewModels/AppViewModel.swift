import AppKit
import Combine
import Foundation

enum CursorOperationState: Equatable {
    case idle
    case working(String)
    case success(String)
    case failure(String)
}

enum AppSection: String, CaseIterable, Identifiable {
    case library
    case marketplace

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .library: L10n.library
        case .marketplace: L10n.marketplace
        }
    }
}

struct PresentedError: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

@MainActor
private struct ModerationCursorTestSession {
    let rootDirectory: URL
    let applier: CoreGraphicsCursorApplier
    let originalTheme: CursorTheme?
}

@MainActor
private final class TestHostCursorApplier: SystemCursorApplying {
    func apply(theme: CursorTheme) async throws {}
    func restoreSystemDefault() async throws {}
}

@MainActor
final class AppViewModel: ObservableObject {
    @Published var selectedThemeID: UUID?
    @Published var selectedSection: AppSection = .library
    @Published var selectedRole: CursorRole = .arrow
    @Published var operationState: CursorOperationState = .idle
    @Published var presentedError: PresentedError?
    @Published var isPrivacyPresented = false
    @Published var isOnboardingPresented = false
    @Published var isDeleteConfirmationPresented = false
    @Published var themeImportDraft: ThemeImportDraft?
    @Published private(set) var moderationTestVersionID: UUID?
    @Published private(set) var isPreparingThemeImport = false
    @Published private(set) var importRequest = 0
    @Published private(set) var themeNameFocusRequest = 0

    let store: ThemeStore
    let paths: ApplicationPaths
    let preferences: AppPreferences
    let marketplaceAccount: MarketplaceAccountViewModel

    private let importer: ImageImportService
    private let capeImporter: CapeImportService
    private let windowsImporter: WindowsCursorImportService
    private let cursorApplier: any SystemCursorApplying
    private let diagnostics: DiagnosticLogger
    private var monitor: CursorReapplicationMonitor?
    private var moderationTestSession: ModerationCursorTestSession?
    private var startupError: Error?
    private var isApplying = false
    private var restoreRequestedWhileApplying = false
    private var cursorIntentRevision = 0
    private var cancellables: Set<AnyCancellable> = []

    convenience init() {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            let paths = ApplicationPaths(
                rootDirectory: FileManager.default.temporaryDirectory.appending(
                    path: "CursorStudioTestHost-\(ProcessInfo.processInfo.processIdentifier)",
                    directoryHint: .isDirectory
                )
            )
            let diagnostics = DiagnosticLogger(paths: paths)
            self.init(
                paths: paths,
                store: ThemeStore(paths: paths),
                importer: ImageImportService(paths: paths),
                capeImporter: CapeImportService(paths: paths),
                windowsImporter: WindowsCursorImportService(paths: paths),
                cursorApplier: TestHostCursorApplier(),
                diagnostics: diagnostics,
                preferences: AppPreferences()
            )
            return
        }

        let paths: ApplicationPaths
        let startupError: Error?
        do {
            paths = try .live()
            startupError = nil
        } catch {
            paths = ApplicationPaths(
                rootDirectory: FileManager.default.temporaryDirectory
                    .appending(path: ProductInfo.name, directoryHint: .isDirectory)
            )
            startupError = CursorStudioError.filePermission(
                "Application Support/\(ProductInfo.name)"
            )
        }

        let diagnostics = DiagnosticLogger(paths: paths)
        self.init(
            paths: paths,
            store: ThemeStore(paths: paths),
            importer: ImageImportService(paths: paths),
            capeImporter: CapeImportService(paths: paths),
            windowsImporter: WindowsCursorImportService(paths: paths),
            cursorApplier: CoreGraphicsCursorApplier(
                paths: paths,
                diagnostics: diagnostics
            ),
            diagnostics: diagnostics,
            preferences: AppPreferences(),
            startupError: startupError
        )
    }

    init(
        paths: ApplicationPaths,
        store: ThemeStore,
        importer: ImageImportService,
        capeImporter: CapeImportService? = nil,
        windowsImporter: WindowsCursorImportService? = nil,
        cursorApplier: any SystemCursorApplying,
        diagnostics: DiagnosticLogger,
        preferences: AppPreferences = AppPreferences(),
        startupError: Error? = nil
    ) {
        self.paths = paths
        self.store = store
        self.importer = importer
        self.capeImporter = capeImporter ?? CapeImportService(paths: paths)
        self.windowsImporter = windowsImporter
            ?? WindowsCursorImportService(paths: paths)
        self.cursorApplier = cursorApplier
        self.diagnostics = diagnostics
        self.preferences = preferences
        marketplaceAccount = MarketplaceAccountViewModel(paths: paths)
        self.startupError = startupError

        store.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        marketplaceAccount.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    isolated deinit {
        monitor?.stop()
    }

    var selectedTheme: CursorTheme? {
        selectedThemeID.flatMap(store.theme(withID:))
    }

    var selectedEntry: CursorEntry? {
        selectedTheme?.entry(for: selectedRole)
    }

    func load() async {
        isOnboardingPresented = !preferences.onboardingCompleted

        if let startupError {
            present(startupError, title: L10n.storageUnavailable)
        }

        do {
            try store.load()
        } catch {
            diagnostics.record(operation: "load-library", error: error)
            if error is CursorStudioError {
                try? await cursorApplier.restoreSystemDefault()
                try? store.setActiveThemeID(nil)
            }
            present(error, title: L10n.libraryRecovered)
        }

        selectedThemeID = store.activeThemeID ?? store.themes.first?.id
        if preferences.keepCursorActiveAfterAppQuit,
           let activeTheme = store.activeTheme {
            // Apply starts with a verified system reset, so this is safe both
            // after a normal relaunch and after a reboot where WindowServer
            // has discarded the previous process's registrations.
            await apply(
                activeTheme,
                isAutomatic: true,
                expectedIntentRevision: cursorIntentRevision
            )
        } else {
            do {
                // A prior WindowServer registration can outlive the app and
                // its theme files. The default mode always starts from the
                // real macOS cursor.
                if store.activeThemeID != nil {
                    try store.setActiveThemeID(nil)
                }
                try await cursorApplier.restoreSystemDefault()
            } catch {
                diagnostics.record(operation: "startup-restore", error: error)
            }
        }

        monitor?.stop()
        monitor = CursorReapplicationMonitor { [weak self] in
            guard let self, self.preferences.autoRecoverCursor else { return }
            await self.reapplyActiveTheme()
        }
        monitor?.start()
        await marketplaceAccount.restoreSessionIfNeeded()
    }

    func createTheme() {
        do {
            let theme = try store.createTheme()
            selectedThemeID = theme.id
            selectedRole = .arrow
            themeNameFocusRequest += 1
            operationState = .success(L10n.newThemeCreated)
        } catch {
            present(error, title: L10n.couldNotCreateTheme)
        }
    }

    func requestDeleteSelectedTheme() {
        if preferences.confirmBeforeDeletingTheme {
            isDeleteConfirmationPresented = true
        } else {
            Task { await deleteSelectedTheme() }
        }
    }

    func mainWindowDidClose() {
        Task {
            if moderationTestSession != nil {
                _ = await stopModerationTest()
            }
            guard !preferences.keepCursorActiveWhenWindowClosed,
                  !preferences.keepCursorActiveAfterAppQuit else {
                return
            }
            await restoreSystemDefault()
        }
    }

    func startModerationTest(
        _ item: MarketplaceModerationItem
    ) async -> Bool {
        if moderationTestSession != nil,
           !(await stopModerationTest()) {
            return false
        }
        guard let validated = await marketplaceAccount
            .prepareModerationTest(item: item) else {
            return false
        }
        defer {
            if let cleanup = validated.cleanupDirectory {
                try? FileManager.default.removeItem(at: cleanup)
            }
        }

        let testRoot = FileManager.default.temporaryDirectory.appending(
            path: "CursorStudioModeratorTest-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let testPaths = ApplicationPaths(rootDirectory: testRoot)
        do {
            operationState = .working(L10n.preparingThemeTest)
            let testStore = ThemeStore(paths: testPaths)
            try testStore.load()
            let testTheme = try MarketplaceInstaller(
                store: testStore,
                paths: testPaths
            ).install(validated)
            let testDiagnostics = DiagnosticLogger(paths: testPaths)
            let testApplier = CoreGraphicsCursorApplier(
                paths: testPaths,
                diagnostics: testDiagnostics
            )
            try await testApplier.apply(theme: testTheme)
            moderationTestSession = ModerationCursorTestSession(
                rootDirectory: testRoot,
                applier: testApplier,
                originalTheme: store.activeTheme
            )
            moderationTestVersionID = item.versionID
            marketplaceAccount.markModerationTested(item)
            operationState = .success(L10n.themeTestActive)
            return true
        } catch {
            try? FileManager.default.removeItem(at: testRoot)
            operationState = .failure(L10n.themeTestFailed)
            present(error, title: L10n.themeTestFailed)
            return false
        }
    }

    @discardableResult
    func stopModerationTest() async -> Bool {
        guard let session = moderationTestSession else { return true }
        do {
            try await session.applier.restoreSystemDefault()
            if let originalTheme = session.originalTheme {
                try await cursorApplier.apply(theme: originalTheme)
            }
            moderationTestSession = nil
            moderationTestVersionID = nil
            try? FileManager.default.removeItem(at: session.rootDirectory)
            operationState = .success(L10n.themeTestStopped)
            return true
        } catch {
            operationState = .failure(L10n.themeTestRestoreFailed)
            present(error, title: L10n.themeTestRestoreFailed)
            return false
        }
    }

    func completeOnboarding() {
        preferences.markOnboardingCompleted()
        isOnboardingPresented = false
    }

    func showOnboarding() {
        preferences.requestOnboardingAgain()
        isOnboardingPresented = true
    }

    func renameSelectedTheme(to name: String) {
        guard let selectedThemeID else { return }
        do {
            try store.renameTheme(id: selectedThemeID, to: name)
        } catch {
            present(error, title: L10n.couldNotRenameTheme)
        }
    }

    func duplicateSelectedTheme() {
        guard let selectedThemeID else { return }
        do {
            let duplicate = try store.duplicateTheme(id: selectedThemeID)
            self.selectedThemeID = duplicate.id
            operationState = .success(L10n.themeDuplicated)
        } catch {
            present(error, title: L10n.couldNotDuplicateTheme)
        }
    }

    func deleteSelectedTheme() async {
        guard let selectedThemeID else { return }
        do {
            if store.activeThemeID == selectedThemeID {
                await restoreSystemDefault()
            }
            try store.deleteTheme(id: selectedThemeID)
            self.selectedThemeID = store.themes.first?.id
            operationState = .success(L10n.themeDeleted)
        } catch {
            diagnostics.record(operation: "delete-theme", error: error)
            present(error, title: L10n.couldNotDeleteTheme)
        }
    }

    func importImage(from url: URL, for role: CursorRole? = nil) {
        guard let themeID = selectedThemeID else {
            present(CursorStudioError.themeNotFound, title: L10n.importFailed)
            return
        }
        let targetRole = role ?? selectedRole
        do {
            let asset = try importer.importImage(from: url, for: themeID)
            let existing = store.theme(withID: themeID)?.entry(for: targetRole)
            let defaultHotspot: CursorHotspot = switch targetRole {
            case .arrow, .pointingHand, .operationNotAllowed, .progress:
                .topLeft
            default:
                .center
            }
            let entry = CursorEntry(
                role: targetRole,
                assetFilename: asset.filename,
                pixelWidth: asset.pixelWidth,
                pixelHeight: asset.pixelHeight,
                hotspot: existing?.hotspot ?? defaultHotspot
            )
            try store.setEntry(entry, in: themeID)
            deactivateThemeAfterEditIfNeeded(themeID)
            selectedRole = targetRole
            operationState = .success(L10n.importedRole(targetRole.displayName))
        } catch {
            diagnostics.record(operation: "import", role: targetRole, error: error)
            present(error, title: L10n.importFailed)
        }
    }

    func importFile(from url: URL, for role: CursorRole? = nil) {
        if CapeImportService.canImport(url) {
            prepareCapeImport(from: url)
        } else if WindowsCursorImportService.canImport(url) {
            prepareWindowsImport(from: url)
        } else {
            importImage(from: url, for: role)
        }
    }

    func cancelThemeImport() {
        guard let draft = themeImportDraft else { return }
        themeImportDraft = nil
        Task {
            if draft.theme.importMetadata?.sourceFormat
                .localizedCaseInsensitiveContains("Windows") == true {
                await windowsImporter.discard(draft)
            } else {
                await capeImporter.discard(draft)
            }
        }
    }

    func commitThemeImport() {
        guard let draft = themeImportDraft else { return }
        do {
            let theme = try store.commitImportedTheme(draft)
            themeImportDraft = nil
            selectedThemeID = theme.id
            selectedRole = .arrow
            operationState = .success(
                L10n.importedRoles(theme.entries.count, theme: theme.name)
            )
        } catch {
            diagnostics.record(operation: "commit-cape-import", error: error)
            present(error, title: L10n.importFailed)
        }
    }

    func requestImport() {
        importRequest += 1
    }

    func updateHotspot(_ hotspot: CursorHotspot) {
        guard let selectedThemeID else { return }
        do {
            try store.setHotspot(
                hotspot,
                role: selectedRole,
                themeID: selectedThemeID
            )
            deactivateThemeAfterEditIfNeeded(selectedThemeID)
        } catch {
            present(error, title: L10n.couldNotSaveHotspot)
        }
    }

    func removeSelectedCursor() {
        guard let selectedThemeID else { return }
        do {
            try store.removeEntry(role: selectedRole, from: selectedThemeID)
            deactivateThemeAfterEditIfNeeded(selectedThemeID)
            operationState = .success(L10n.removedRole(selectedRole.displayName))
        } catch {
            present(error, title: L10n.couldNotRemoveCursor)
        }
    }

    func applySelectedTheme() async {
        guard let selectedTheme else { return }
        cursorIntentRevision += 1
        await apply(
            selectedTheme,
            isAutomatic: false,
            expectedIntentRevision: cursorIntentRevision
        )
    }

    func restoreSystemDefault() async {
        cursorIntentRevision += 1
        monitor?.cancelPending()
        do {
            if store.activeThemeID != nil {
                try store.setActiveThemeID(nil)
            }
        } catch {
            diagnostics.record(operation: "clear-active-before-restore", error: error)
        }
        if isApplying {
            restoreRequestedWhileApplying = true
            operationState = .working(L10n.restoringCursor)
            return
        }
        isApplying = true
        operationState = .working(L10n.restoringCursor)
        defer { isApplying = false }

        do {
            try await cursorApplier.restoreSystemDefault()
            operationState = .success(L10n.cursorRestored)
        } catch {
            operationState = .failure(L10n.restoreFailed)
            diagnostics.record(operation: "restore", error: error)
            present(error, title: L10n.restoreFailedTitle)
        }
    }

    func showDiagnosticLog() {
        do {
            let url = try diagnostics.ensureLogExists()
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            present(error, title: L10n.logUnavailable)
        }
    }

    private func reapplyActiveTheme() async {
        guard let active = store.activeTheme, !isApplying else { return }
        let expectedRevision = cursorIntentRevision
        await apply(
            active,
            isAutomatic: true,
            expectedIntentRevision: expectedRevision
        )
    }

    private func prepareCapeImport(from url: URL) {
        guard !isPreparingThemeImport, themeImportDraft == nil else { return }
        isPreparingThemeImport = true
        operationState = .working(L10n.reading(url.lastPathComponent))

        Task {
            defer { isPreparingThemeImport = false }
            do {
                let draft = try await capeImporter.prepareImport(from: url)
                themeImportDraft = draft
                operationState = .success(L10n.capeReadyForReview)
            } catch {
                diagnostics.record(operation: "prepare-cape-import", error: error)
                operationState = .failure(L10n.capeImportFailed)
                present(error, title: L10n.importFailed)
            }
        }
    }

    private func prepareWindowsImport(from url: URL) {
        guard !isPreparingThemeImport, themeImportDraft == nil else { return }
        isPreparingThemeImport = true
        operationState = .working(L10n.reading(url.lastPathComponent))

        Task {
            defer { isPreparingThemeImport = false }
            do {
                let draft = try await windowsImporter.prepareImport(from: url)
                themeImportDraft = draft
                operationState = .success(L10n.themeReadyForReview)
            } catch {
                diagnostics.record(
                    operation: "prepare-windows-import",
                    error: error
                )
                operationState = .failure(L10n.themeImportFailed)
                present(error, title: L10n.importFailed)
            }
        }
    }

    private func deactivateThemeAfterEditIfNeeded(_ themeID: UUID) {
        guard store.activeThemeID == themeID else { return }
        do {
            try store.setActiveThemeID(nil)
            operationState = .working(L10n.restoringAfterEdit)
            Task {
                while isApplying {
                    try? await Task.sleep(for: .milliseconds(50))
                }
                guard !Task.isCancelled else { return }
                await restoreSystemDefault()
            }
        } catch {
            diagnostics.record(operation: "deactivate-edited-theme", error: error)
            present(error, title: L10n.couldNotDeactivateTheme)
        }
    }

    private func apply(
        _ theme: CursorTheme,
        isAutomatic: Bool,
        expectedIntentRevision: Int
    ) async {
        guard expectedIntentRevision == cursorIntentRevision else { return }
        guard !isApplying else { return }
        isApplying = true
        restoreRequestedWhileApplying = false
        if !isAutomatic {
            operationState = .working(L10n.applying(theme.name))
        }
        defer {
            isApplying = false
            if restoreRequestedWhileApplying {
                restoreRequestedWhileApplying = false
                Task { @MainActor [weak self] in
                    await self?.restoreSystemDefault()
                }
            }
        }

        do {
            try await cursorApplier.apply(theme: theme)
            guard !restoreRequestedWhileApplying,
                  expectedIntentRevision == cursorIntentRevision else {
                return
            }
            try store.setActiveThemeID(theme.id)
            operationState = .success(
                isAutomatic ? L10n.themeIsActive(theme.name) : L10n.themeApplied
            )
        } catch {
            try? store.setActiveThemeID(nil)
            operationState = .failure(L10n.applyFailed)
            diagnostics.record(operation: "apply-theme", error: error)
            if !isAutomatic {
                present(error, title: L10n.applyFailedTitle)
            }
        }
    }

    func prepareForApplicationTermination() {
        monitor?.stop()
        restoreRequestedWhileApplying = false
        if preferences.keepCursorActiveAfterAppQuit,
           store.activeThemeID != nil,
           moderationTestSession == nil,
           !isApplying {
            return
        }
        try? store.setActiveThemeID(nil)
        guard let immediate = cursorApplier as? ImmediateSystemCursorRestoring else {
            return
        }
        do {
            try immediate.restoreSystemDefaultImmediately()
        } catch {
            diagnostics.record(operation: "termination-restore", error: error)
        }
    }

    private func present(_ error: Error, title: String) {
        presentedError = PresentedError(
            title: title,
            message: error.localizedDescription
        )
    }
}
