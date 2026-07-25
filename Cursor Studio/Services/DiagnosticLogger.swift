import Foundation
import OSLog

final class DiagnosticLogger {
    private let paths: ApplicationPaths
    private let fileManager: FileManager
    private let logger = Logger(
        subsystem: ProductInfo.bundleIdentifier,
        category: "CursorApplication"
    )
    private let formatter = ISO8601DateFormatter()

    init(paths: ApplicationPaths, fileManager: FileManager = .default) {
        self.paths = paths
        self.fileManager = fileManager
    }

    func record(
        operation: String,
        role: CursorRole? = nil,
        error: Error
    ) {
        let message = [
            formatter.string(from: .now),
            "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)",
            "operation=\(sanitize(operation))",
            "role=\(role?.rawValue ?? "none")",
            "error=\(sanitize(error.localizedDescription))",
        ].joined(separator: " | ") + "\n"

        logger.error("\(message, privacy: .public)")

        do {
            try paths.createDirectories(fileManager: fileManager)
            try rotateIfNeeded()
            if !fileManager.fileExists(atPath: paths.diagnosticLog.path) {
                try Data().write(to: paths.diagnosticLog, options: .atomic)
            }
            let handle = try FileHandle(forWritingTo: paths.diagnosticLog)
            defer { try? handle.close() }
            try handle.seekToEnd()
            if let data = message.data(using: .utf8) {
                try handle.write(contentsOf: data)
            }
        } catch {
            logger.error("Unable to write local diagnostic log: \(error.localizedDescription, privacy: .public)")
        }
    }

    func ensureLogExists() throws -> URL {
        try paths.createDirectories(fileManager: fileManager)
        if !fileManager.fileExists(atPath: paths.diagnosticLog.path) {
            let header = """
            Cursor Studio diagnostic log
            No cursor-application failures have been recorded.

            """
            try Data(header.utf8).write(to: paths.diagnosticLog, options: .atomic)
        }
        return paths.diagnosticLog
    }

    private func rotateIfNeeded() throws {
        guard let attributes = try? fileManager.attributesOfItem(
            atPath: paths.diagnosticLog.path
        ), let size = attributes[.size] as? NSNumber,
           size.intValue >= ProductInfo.diagnosticLogLimit else {
            return
        }

        let rotated = paths.logsDirectory.appending(
            path: "diagnostics.previous.log",
            directoryHint: .notDirectory
        )
        if fileManager.fileExists(atPath: rotated.path) {
            try fileManager.removeItem(at: rotated)
        }
        try fileManager.moveItem(at: paths.diagnosticLog, to: rotated)
    }

    private func sanitize(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .prefix(1_000)
            .description
    }
}
