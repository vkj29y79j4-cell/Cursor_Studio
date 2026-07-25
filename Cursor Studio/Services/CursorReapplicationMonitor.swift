import AppKit
import Foundation

@MainActor
final class CursorReapplicationMonitor {
    private var tokens: [NSObjectProtocol] = []
    private var pendingTask: Task<Void, Never>?
    private let handler: @MainActor () async -> Void

    init(handler: @escaping @MainActor () async -> Void) {
        self.handler = handler
    }

    var registeredObserverCount: Int {
        tokens.count
    }

    func start() {
        guard tokens.isEmpty else { return }

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        tokens.append(
            workspaceCenter.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.schedule() }
            }
        )
        tokens.append(
            workspaceCenter.addObserver(
                forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.schedule() }
            }
        )

        let notificationCenter = NotificationCenter.default
        for name in [
            NSApplication.didChangeScreenParametersNotification,
            NSApplication.didBecomeActiveNotification,
        ] {
            tokens.append(
                notificationCenter.addObserver(
                    forName: name,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    Task { @MainActor in self?.schedule() }
                }
            )
        }
    }

    func stop() {
        cancelPending()
        for token in tokens {
            NotificationCenter.default.removeObserver(token)
            NSWorkspace.shared.notificationCenter.removeObserver(token)
        }
        tokens.removeAll()
    }

    func cancelPending() {
        pendingTask?.cancel()
        pendingTask = nil
    }

    private func schedule() {
        pendingTask?.cancel()
        pendingTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(750))
            guard !Task.isCancelled, let self else { return }
            await handler()
        }
    }
}
