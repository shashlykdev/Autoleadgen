import Foundation
import Combine
import os.log
import SwiftUI

struct LogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let level: LogLevel
    let message: String

    enum LogLevel: String {
        case info = "INFO"
        case warning = "WARN"
        case error = "ERROR"
        case debug = "DEBUG"

        var color: Color {
            switch self {
            case .info: return .primary
            case .warning: return .orange
            case .error: return .red
            case .debug: return .gray
            }
        }

        var icon: String {
            switch self {
            case .info: return "info.circle"
            case .warning: return "exclamationmark.triangle"
            case .error: return "xmark.circle"
            case .debug: return "ant"
            }
        }
    }

    var formattedTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: timestamp)
    }
}

@MainActor
class LoggingService: ObservableObject {
    @Published var entries: [LogEntry] = []
    private let logger = Logger(subsystem: "com.autoleadgen", category: "automation")
    private let maxEntries = 500

    func log(_ message: String, level: LogEntry.LogLevel = .info) {
        let entry = LogEntry(timestamp: Date(), level: level, message: message)
        entries.append(entry)

        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }

        switch level {
        case .info:
            logger.info("\(message)")
        case .warning:
            logger.warning("\(message)")
        case .error:
            logger.error("\(message)")
        case .debug:
            logger.debug("\(message)")
        }
    }

    func info(_ message: String) {
        log(message, level: .info)
    }

    func warning(_ message: String) {
        log(message, level: .warning)
    }

    func error(_ message: String) {
        log(message, level: .error)
    }

    func debug(_ message: String) {
        log(message, level: .debug)
    }

    func clear() {
        entries.removeAll()
    }
}
