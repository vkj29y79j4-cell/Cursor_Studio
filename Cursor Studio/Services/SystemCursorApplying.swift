import Foundation

@MainActor
protocol SystemCursorApplying {
    func apply(theme: CursorTheme) async throws
    func restoreSystemDefault() async throws
}

/// Used by the app-termination hook, where an asynchronous Task may be killed
/// before WindowServer receives the reset.
@MainActor
protocol ImmediateSystemCursorRestoring {
    func restoreSystemDefaultImmediately() throws
}
