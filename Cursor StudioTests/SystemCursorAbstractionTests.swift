import XCTest
@testable import Cursor_Studio

final class SystemCursorAbstractionTests: XCTestCase {
    @MainActor
    func testMockCanApplyPartialThemeAndRestore() async throws {
        let mock = MockSystemCursorApplier()
        let theme = CursorTheme(
            name: "Partial",
            entries: [
                CursorEntry(
                    role: .arrow,
                    assetFilename: "arrow.png",
                    pixelWidth: 64,
                    pixelHeight: 64
                ),
            ]
        )

        try await mock.apply(theme: theme)
        try await mock.restoreSystemDefault()

        XCTAssertEqual(mock.appliedThemes, [theme])
        XCTAssertEqual(mock.restoreCount, 1)
    }

    @MainActor
    func testRestoreIsRepeatableAndClearsActiveThemeState() async throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "CursorStudioRestoreTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = ApplicationPaths(rootDirectory: root)
        let store = ThemeStore(paths: paths)
        try store.load()
        let theme = try store.createTheme(named: "Active")
        try store.setActiveThemeID(theme.id)
        let mock = MockSystemCursorApplier()
        let diagnostics = DiagnosticLogger(paths: paths)
        let model = AppViewModel(
            paths: paths,
            store: store,
            importer: ImageImportService(paths: paths),
            cursorApplier: mock,
            diagnostics: diagnostics
        )

        for _ in 0..<5 {
            await model.restoreSystemDefault()
        }

        XCTAssertEqual(mock.restoreCount, 5)
        XCTAssertNil(store.activeThemeID)
    }

    @MainActor
    func testOrdinaryRelaunchRestoresSystemCursor() async throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "CursorStudioRelaunchTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let defaults = try XCTUnwrap(
            UserDefaults(
                suiteName: "CursorStudioRelaunchTests.\(UUID().uuidString)"
            )
        )
        let preferences = AppPreferences(
            defaults: defaults,
            launchAtLoginOverride: true
        )
        let paths = ApplicationPaths(rootDirectory: root)
        let store = ThemeStore(paths: paths)
        try store.load()
        let theme = try XCTUnwrap(store.themes.first)
        try store.setActiveThemeID(theme.id)
        let mock = MockSystemCursorApplier()
        let model = AppViewModel(
            paths: paths,
            store: store,
            importer: ImageImportService(paths: paths),
            cursorApplier: mock,
            diagnostics: DiagnosticLogger(paths: paths),
            preferences: preferences
        )

        await model.load()

        XCTAssertEqual(mock.restoreCount, 1)
        XCTAssertTrue(mock.appliedThemes.isEmpty)
        XCTAssertNil(store.activeThemeID)
    }

    @MainActor
    func testPersistentModeReappliesActiveThemeOnRelaunch() async throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "CursorStudioPersistentRelaunchTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let defaults = try XCTUnwrap(
            UserDefaults(
                suiteName: "CursorStudioPersistentRelaunchTests.\(UUID().uuidString)"
            )
        )
        let preferences = AppPreferences(
            defaults: defaults,
            launchAtLoginOverride: true
        )
        preferences.keepCursorActiveAfterAppQuit = true
        let paths = ApplicationPaths(rootDirectory: root)
        let store = ThemeStore(paths: paths)
        try store.load()
        let theme = try XCTUnwrap(store.themes.first)
        try store.setActiveThemeID(theme.id)
        let mock = MockSystemCursorApplier()
        let model = AppViewModel(
            paths: paths,
            store: store,
            importer: ImageImportService(paths: paths),
            cursorApplier: mock,
            diagnostics: DiagnosticLogger(paths: paths),
            preferences: preferences
        )

        await model.load()

        XCTAssertEqual(mock.appliedThemes.count, 1)
        XCTAssertEqual(mock.appliedThemes.first?.id, theme.id)
        XCTAssertEqual(mock.appliedThemes.first?.entries.count, theme.entries.count)
        XCTAssertEqual(
            mock.appliedThemes.first?.entries.first?.assetFilename,
            theme.entries.first?.assetFilename
        )
        XCTAssertEqual(mock.restoreCount, 0)
        XCTAssertEqual(store.activeThemeID, theme.id)
    }

    @MainActor
    func testRestoreQueuedDuringApplyWinsAndCannotBeReapplied() async throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "CursorStudioRestoreRaceTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = ApplicationPaths(rootDirectory: root)
        let store = ThemeStore(paths: paths)
        try store.load()
        let mock = MockSystemCursorApplier()
        mock.applyDelay = .milliseconds(80)
        let model = AppViewModel(
            paths: paths,
            store: store,
            importer: ImageImportService(paths: paths),
            cursorApplier: mock,
            diagnostics: DiagnosticLogger(paths: paths)
        )
        await model.load()

        let applyTask = Task { await model.applySelectedTheme() }
        for _ in 0..<100 where !mock.isApplying {
            await Task.yield()
        }
        await model.restoreSystemDefault()
        await applyTask.value
        for _ in 0..<100 where mock.restoreCount < 2 {
            try await Task.sleep(for: .milliseconds(5))
        }

        XCTAssertEqual(mock.appliedThemes.count, 1)
        XCTAssertEqual(mock.restoreCount, 2)
        XCTAssertNil(store.activeThemeID)
    }

    @MainActor
    func testTerminationUsesImmediateRestoreAndClearsState() throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "CursorStudioTerminationTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = ApplicationPaths(rootDirectory: root)
        let store = ThemeStore(paths: paths)
        try store.load()
        let theme = try XCTUnwrap(store.themes.first)
        try store.setActiveThemeID(theme.id)
        let mock = MockSystemCursorApplier()
        let model = AppViewModel(
            paths: paths,
            store: store,
            importer: ImageImportService(paths: paths),
            cursorApplier: mock,
            diagnostics: DiagnosticLogger(paths: paths)
        )

        model.prepareForApplicationTermination()

        XCTAssertEqual(mock.immediateRestoreCount, 1)
        XCTAssertNil(store.activeThemeID)
    }

    @MainActor
    func testPersistentModeKeepsCursorAndActiveThemeAtTermination() throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "CursorStudioPersistentTerminationTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let defaults = try XCTUnwrap(
            UserDefaults(
                suiteName: "CursorStudioPersistentTerminationTests.\(UUID().uuidString)"
            )
        )
        let preferences = AppPreferences(
            defaults: defaults,
            launchAtLoginOverride: true
        )
        preferences.keepCursorActiveAfterAppQuit = true
        let paths = ApplicationPaths(rootDirectory: root)
        let store = ThemeStore(paths: paths)
        try store.load()
        let theme = try XCTUnwrap(store.themes.first)
        try store.setActiveThemeID(theme.id)
        let mock = MockSystemCursorApplier()
        let model = AppViewModel(
            paths: paths,
            store: store,
            importer: ImageImportService(paths: paths),
            cursorApplier: mock,
            diagnostics: DiagnosticLogger(paths: paths),
            preferences: preferences
        )

        model.prepareForApplicationTermination()

        XCTAssertEqual(mock.immediateRestoreCount, 0)
        XCTAssertEqual(store.activeThemeID, theme.id)
    }

    @MainActor
    func testMonitorDoesNotDuplicateObserversAndStopsCleanly() {
        let monitor = CursorReapplicationMonitor {}

        monitor.start()
        XCTAssertEqual(monitor.registeredObserverCount, 4)
        monitor.start()
        XCTAssertEqual(monitor.registeredObserverCount, 4)
        monitor.stop()
        XCTAssertEqual(monitor.registeredObserverCount, 0)
    }
}

@MainActor
private final class MockSystemCursorApplier:
    SystemCursorApplying,
    ImmediateSystemCursorRestoring
{
    private(set) var appliedThemes: [CursorTheme] = []
    private(set) var restoreCount = 0
    private(set) var immediateRestoreCount = 0
    private(set) var isApplying = false
    var applyDelay: Duration?

    func apply(theme: CursorTheme) async throws {
        isApplying = true
        defer { isApplying = false }
        appliedThemes.append(theme)
        if let applyDelay {
            try await Task.sleep(for: applyDelay)
        }
    }

    func restoreSystemDefault() async throws {
        restoreCount += 1
    }

    func restoreSystemDefaultImmediately() throws {
        immediateRestoreCount += 1
    }
}
