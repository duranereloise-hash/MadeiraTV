import Foundation
import SwiftUI

/// tvOS-минимальная версия LogStore: без Wine/JIT C-колбэков, просто
/// кольцевой список записей + запись в stderr. Полная версия (с тайл-реадером
/// лога Wine) подключается на Фазе 2 вместе с Wine-библиотеками.
final class LogStore: ObservableObject {
    static let shared = LogStore()

    struct LogEntry: Identifiable, Equatable {
        enum Level: Int {
            case info = 0, success, warning, error
        }
        var id: UUID = UUID()
        var timestamp: Date = Date()
        var message: String
        var level: Level = .info
    }

    @Published var entries: [LogEntry] = []

    private let maxEntries = 500
    private let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    private init() {}

    func log(_ message: String, level: LogEntry.Level = .info) {
        let ts = formatter.string(from: Date())
        let badge: String
        switch level {
        case .info: badge = "INFO"
        case .success: badge = " OK "
        case .warning: badge = "WARN"
        case .error: badge = "ERR "
        }
        fputs("[\(ts)] [\(badge)] \(message)\n", stderr)
        let entry = LogEntry(message: message, level: level)
        DispatchQueue.main.async {
            self.entries.append(entry)
            if self.entries.count > self.maxEntries {
                self.entries.removeFirst(self.entries.count - self.maxEntries)
            }
        }
    }

    func clear() {
        entries.removeAll()
    }
}

// Тип, который используется другими файлами (LogPattern canonicalize).
extension LogStore.LogEntry.Level {
    static func from(_ raw: String) -> LogStore.LogEntry.Level {
        switch raw.uppercased() {
        case "ERROR", "ERR": return .error
        case "WARN", "WARNING": return .warning
        case "SUCCESS", "OK": return .success
        default: return .info
        }
    }
}