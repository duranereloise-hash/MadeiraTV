// SPDX-License-Identifier: GPL-3.0-or-later
//
// Ring-buffer journal of launch transitions, persisted as JSONL at
// Library/Caches/launches.jsonl (max 50 lines), served at GET /journal.

import Foundation

final class LaunchJournal {
    static let shared = LaunchJournal()

    private let lock = NSLock()
    private var current: [String: Any] = [:]

    static var fileURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("launches.jsonl")
    }

    private init() {}

    func begin(appID: UInt32, appName: String) {
        lock.lock()
        current = [
            "startedAt": Int(Date().timeIntervalSince1970),
            "appID": appID,
            "appName": appName,
            "phasesReached": [String](),
            "presentCountFinal": 0,
            "result": "running",
            "elapsedMs": 0,
        ]
        lock.unlock()
    }

    func phase(_ name: String) {
        lock.lock()
        var arr = (current["phasesReached"] as? [String]) ?? []
        if !arr.contains(name) { arr.append(name) }
        current["phasesReached"] = arr
        lock.unlock()
    }

    func record(appID: UInt32, appName: String, result: String, presentCount: UInt64) {
        lock.lock()
        var rec = current
        if rec["appID"] == nil {
            rec["appID"] = appID
            rec["appName"] = appName
            rec["startedAt"] = Int(Date().timeIntervalSince1970)
        }
        let start = (rec["startedAt"] as? Int) ?? Int(Date().timeIntervalSince1970)
        rec["result"] = result
        rec["presentCountFinal"] = presentCount
        rec["elapsedMs"] = Int(Date().timeIntervalSince1970) * 1000 - start * 1000
        current = rec
        lock.unlock()

        var line = "{"
        if JSONSerialization.isValidJSONObject(rec),
           let data = try? JSONSerialization.data(withJSONObject: rec) {
            line = String(data: data, encoding: .utf8) ?? "{"
        }
        appendLine(line)
    }

    func jsonString() -> String {
        lock.lock()
        let lines = loadLines()
        lock.unlock()
        return "[\n" + lines.joined(separator: ",\n") + "\n]"
    }

    private func appendLine(_ line: String) {
        var lines = loadLines()
        lines.append(line)
        while lines.count > 50 { lines.removeFirst() }
        let text = lines.joined(separator: "\n") + "\n"
        try? text.data(using: .utf8)?.write(to: Self.fileURL, options: .atomic)
    }

    private func loadLines() -> [String] {
        (try? String(contentsOf: Self.fileURL, encoding: .utf8))?
            .split(separator: "\n").map(String.init) ?? []
    }
}