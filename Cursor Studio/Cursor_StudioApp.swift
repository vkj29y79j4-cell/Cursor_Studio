import SwiftUI

@main
struct CursorStudioApp: App {
    @StateObject private var model = AppViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
        }
        .windowStyle(.automatic)
        .defaultSize(width: 1_180, height: 760)
        .commands {
            CommandGroup(after: .newItem) {
                Button(L10n.importCursorImage) {
                    model.requestImport()
                }
                .keyboardShortcut("i", modifiers: .command)

                Button(L10n.duplicateTheme) {
                    model.duplicateSelectedTheme()
                }
                .keyboardShortcut("d", modifiers: .command)
                .disabled(model.selectedThemeID == nil)
            }

            CommandMenu(L10n.settingsCursor) {
                Button(L10n.applyTheme) {
                    Task { await model.applySelectedTheme() }
                }
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(model.selectedTheme?.entries.isEmpty != false)

                Button(L10n.restoreMacOSCursor) {
                    Task { await model.restoreSystemDefault() }
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            }

            CommandGroup(after: .help) {
                Button(L10n.showDiagnosticLog) {
                    model.showDiagnosticLog()
                }
                Button(L10n.privacyAndCompatibility) {
                    model.isPrivacyPresented = true
                }
            }
        }

        Settings {
            SettingsView(model: model)
        }
    }
}
