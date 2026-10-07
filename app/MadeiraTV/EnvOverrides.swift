// SPDX-License-Identifier: GPL-3.0-or-later
//
// Caches-backed environment overrides. A JSON dict persisted at
// Library/Caches/env-overrides.json and integrated into the launch flow by
// SteamTVLibrary.launch() right BEFORE wineserver_start.
//
// Effective-time notes:
//  • MADEIRA_JIT_POOL_MB is read ONCE per process by jit_pool_init()
//    (FEXBridge.mm) — applying it at launch does NOT resize a pool that was
//    created at app start; it only takes effect on the next app restart.
//  • Keys that wine_process_thread sets unconditionally (e.g. MADEIRA_QUIET)
//    will win over an earlier override; for those also write the matching
//    "env.NAME = value" line into Documents/madeira.cfg (the C config block
//    setenv()s every env.* line after this override point).

import Foundation

final class EnvOverrides {
    static let shared = EnvOverrides()

    private let lock = NSLock()
    private var cache: [String: String] = [:]

    private init() {
        cache = load()
    }

    static var fileURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("env-overrides.json")
    }

    private func load() -> [String: String] {
        guard let data = try? Data(contentsOf: Self.fileURL),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return [:] }
        var out: [String: String] = [:]
        for (k, v) in obj { out[k] = "\(v)" }
        return out
    }

    func dict() -> [String: String] {
        lock.lock(); defer { lock.unlock() }
        return cache
    }

    var current: [String: String] {
        lock.lock(); defer { lock.unlock() }
        return cache
    }

    func get(_ key: String) -> String {
        lock.lock(); defer { lock.unlock() }
        return cache[key] ?? ""
    }

    func save(_ new: [String: String]) {
        lock.lock()
        cache = new
        lock.unlock()
        try? JSONSerialization.data(withJSONObject: new, options: [.prettyPrinted])
            .write(to: Self.fileURL, options: .atomic)
        CrashCatcher.write("[env] saved \(new.count) override(s)")
    }

    /// Call from SteamTVLibrary.launch() BEFORE wineserver_start.
    func integrateIntoLaunch() {
        lock.lock()
        let snapshot = cache
        lock.unlock()
        for (k, v) in snapshot {
            setenv(k, v, 1)
        }
        if !snapshot.isEmpty {
            CrashCatcher.write("[env] integrateIntoLaunch applied \(snapshot.count) override(s)")
        }
    }
}