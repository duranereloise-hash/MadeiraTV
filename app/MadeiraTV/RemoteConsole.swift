// SPDX-License-Identifier: GPL-3.0-or-later
//
// Remote console helpers: status/routes/panel/journal payloads, and the
// POST /action dispatcher. Interfaces to the app through SteamTVLibrary (the
// @MainActor ObservableObject), LaunchJournal and EnvOverrides.
//
// Security (home LAN): no auth. The whole server already binds 0.0.0.0:9090
// inside the app container, which is acceptable for a home network. Optional
// single-line token gate via MADEIRA_CONSOLE_TOKEN (see authorized()).

import Foundation
import os

enum RemoteConsole {

    // MARK: - JSON helpers

    static func json(_ obj: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: obj, options: []) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    /// Optional 1-line token check for POST /action.
    static func authorized(token: String?) -> Bool {
        let expected = EnvOverrides.shared.get("MADEIRA_CONSOLE_TOKEN")
        return expected.isEmpty || token == expected
    }

    // MARK: - /status

    static func statusJSON() -> String {
        let off = fex_get_jit_write_offset()
        var mem = UInt64(0)
        mem = UInt64(os_proc_available_memory())
        let crashTail = TVLogServer.tail(CrashCatcher.logURL, maxLines: 8)
        let obj: [String: Any] = [
            "ip": TVLogServer.localIP() ?? NSNull(),
            "health": true,
            "uptimeS": Int(ProcessInfo.processInfo.systemUptime),
            "jitEnabled": off != 0,
            "jitOffset": off,
            "presentCount": madeira_get_present_count(),
            "wineserverRunning": wineserver_is_running() != 0,
            "wineRunning": wine_process_is_running() != 0,
            "wsMainEntered": g_ws_main_entered != 0,
            "wsInMainloop": g_ws_in_mainloop != 0,
            "availableMemoryBytes": mem,
            "crashTail": crashTail,
            "envOverrides": EnvOverrides.shared.dict(),
        ]
        return json(obj)
    }

    // MARK: - /routes

    static func routesJSON() -> String {
        let routes: [[String: String]] = [
            ["method": "GET", "path": "/log", "desc": "log.txt"],
            ["method": "GET", "path": "/wine", "desc": "madeira-log.txt (Caches)"],
            ["method": "GET", "path": "/srv", "desc": "madeira-log.txt (Documents/wineserver)"],
            ["method": "GET", "path": "/crash", "desc": "crash.log (CrashCatcher)"],
            ["method": "GET", "path": "/all", "desc": "log.txt + both madeira-log tails"],
            ["method": "GET", "path": "/ip", "desc": "local IP"],
            ["method": "GET", "path": "/health", "desc": "{ok:true}"],
            ["method": "GET", "path": "/jit", "desc": "re-arm JIT then report offset"],
            ["method": "GET", "path": "/jitstatus", "desc": "JIT offset only"],
            ["method": "GET", "path": "/status", "desc": "full console status JSON"],
            ["method": "GET", "path": "/routes", "desc": "this catalog"],
            ["method": "GET", "path": "/journal", "desc": "launch journal (JSON ring)"],
            ["method": "GET", "path": "/panel", "desc": "self-contained control panel"],
            ["method": "POST", "path": "/action", "desc": "launch|stop|restart-wineserver|rearm-jit|set-env|dump-vm|snapshot|reboot-app"],
        ]
        return json(["ip": TVLogServer.localIP() ?? NSNull(), "routes": routes])
    }

    // MARK: - POST /action

    static func handleAction(body: String) -> (String, String, String) {
        guard let data = body.data(using: .utf8),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let action = obj["action"] as? String else {
            return ("400 Bad Request", "application/json", json(["error": "expected JSON {action,...}"]))
        }

        if !authorized(token: obj["token"] as? String) {
            return ("401 Unauthorized", "application/json", json(["error": "bad token"]))
        }

        let env = obj["env"] as? [String: Any]
        let appID = (obj["app"] as? NSNumber)?.uint32Value

        if action == "set-env" {
            guard let env, !env.isEmpty else {
                return ("400 Bad Request", "application/json", json(["error": "set-env needs env {}"]))
            }
            var merged = EnvOverrides.shared.current
            for (k, v) in env { merged[k] = "\(v)" }
            EnvOverrides.shared.save(merged)
            let note = merged["MADEIRA_JIT_POOL_MB"] != nil
                ? "JIT pool size applies on the NEXT app restart (read once per process)."
                : "Applied at next launch."
            return ("200 OK", "application/json", json(["ok": true, "saved": merged, "note": note]))
        }

        // Everything else is fire-and-forget; report "accepted" immediately.
        DispatchQueue.global(qos: .userInitiated).async {
            execute(action: action, appID: appID, env: env)
        }
        return ("202 Accepted", "application/json", json(["accepted": action]))
    }

    /// Runs on a background queue; hops to MainActor for UI-touching actions.
    private static func execute(action: String, appID: UInt32?, env: [String: Any]?) {
        let lib = SteamTVLibrary.shared

        switch action {
        case "launch":
            // games lives on the MainActor; hop before touching it.
            DispatchQueue.main.async {
                guard let appID, let app = Self.findApp(appID) else {
                    CrashCatcher.write("[panel] launch: app \(appID ?? 0) not found")
                    return
                }
                if let env, !env.isEmpty {
                    var merged = EnvOverrides.shared.current
                    for (k, v) in env { merged[k] = "\(v)" }
                    EnvOverrides.shared.save(merged)
                }
                CrashCatcher.write("[panel] launch requested app=\(appID)")
                EnvOverrides.shared.integrateIntoLaunch()
                let lib = SteamTVLibrary.shared
                lib.launch(app) { message in
                    LaunchJournal.shared.record(appID: appID, appName: app.name,
                                                result: message ?? "ok",
                                                presentCount: madeira_get_present_count())
                    CrashCatcher.write("[panel] launch completion msg=\(message ?? "ok")")
                }
            }

        case "stop":
            CrashCatcher.write("[panel] stop requested")
            DispatchQueue.main.async { SteamTVLibrary.shared.stopGame() }

        case "restart-wineserver":
            CrashCatcher.write("[panel] restart-wineserver")
            if wineserver_is_running() != 0 { wineserver_stop() }
            usleep(300_000)
            // SteamTVLibrary.prefix is MainActor-isolated; grab it on the main queue.
            let pfix = DispatchQueue.main.sync { return SteamTVLibrary.prefix }
            _ = wineserver_start(pfix.path)

        case "rearm-jit":
            CrashCatcher.write("[panel] rearm-jit")
            DispatchQueue.main.async { lib.rearmJIT() }

        case "dump-vm":
            let mem = UInt64(os_proc_available_memory())
            let off = fex_get_jit_write_offset()
            CrashCatcher.write("[panel] dump-vm availMB=\(mem / 1_048_576) jitOffset=\(off) present=\(madeira_get_present_count()) wsRunning=\(wineserver_is_running()) wineRunning=\(wine_process_is_running())")

        case "snapshot":
            let ts = Int(Date().timeIntervalSince1970)
            let obj: [String: Any] = [
                "id": "snapshot-\(ts)",
                "createdAt": ts,
                "presentCount": madeira_get_present_count(),
                "wineserverRunning": wineserver_is_running() != 0,
                "wineRunning": wine_process_is_running() != 0,
                "crashTail": TVLogServer.tail(CrashCatcher.logURL, maxLines: 60),
            ]
            let file = crashDir().appendingPathComponent("snapshot-\(ts).json")
            try? json(obj).write(to: file, atomically: true, encoding: .utf8)
            CrashCatcher.write("[panel] snapshot wrote=\(file.lastPathComponent)")

        case "reboot-app":
            CrashCatcher.write("[panel] reboot-app: not auto-executed — force-quit MadeiraTV in the tvOS app switcher.")

        default:
            CrashCatcher.write("[panel] unknown action \(action)")
        }
    }

    @MainActor
    private static func findApp(_ id: UInt32) -> SteamAppInfo? {
        SteamTVLibrary.shared.games.first { $0.appID == id }
    }

    private static func crashDir() -> URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    }

    // MARK: - /panel (self-contained HTML)

    static let panelHTML = RemotePanelHTML.source
}