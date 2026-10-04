import Foundation
import SwiftUI

/// tvOS-минимальная версия LogStore: без Wine/JIT C-колбэков, просто
/// кольцевой список записей + запись в stderr и в файл
/// Library/Caches/log.txt (когда Documents недоступен в сайдлоаде).
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

    /// File-backed log under Library/Caches (always writable on tvOS).
    static var logFileURL: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("log.txt", isDirectory: false)
    }

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
        let line = "[\(ts)] [\(badge)] \(message)"
        fputs(line + "\n", stderr)
        // Append to the file (single line, no locking needed at this volume).
        if let handle = try? FileHandle(forWritingTo: Self.logFileURL) {
            handle.seekToEndOfFile()
            handle.write((line + "\n").data(using: .utf8) ?? Data())
            try? handle.close()
        } else {
            // Create it on first write.
            try? (line + "\n").data(using: .utf8)?.write(to: Self.logFileURL, options: .atomic)
        }
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
        try? FileManager.default.removeItem(at: Self.logFileURL)
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