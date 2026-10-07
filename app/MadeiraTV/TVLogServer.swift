// SPDX-License-Identifier: GPL-3.0-or-later
// Madeira Converter Exception: see LICENSE-EXCEPTION.md
//
// Refactored HTTP console on :9090 (bound 0.0.0.0, LAN-only, no auth).
// Keeps every GET route and adds:
//   GET /status  /routes  /panel  /journal
//   POST /action (JSON {action, app?, env?}) — parses a body of any size.
//
// LAN-only by design. Optional single-line token guard is in
// RemoteConsole.authorize(). "Reboot-app" is intentionally a prompt (we never
// exit(0) the app process from a socket handler).

import Foundation
import Network

enum TVLogServer {
    static let port: NWEndpoint.Port = 9090

    static func start() {
        LogStore.shared.log("[logserver] starting on :\(port.rawValue)")
        let listener: NWListener
        do {
            listener = try NWListener(using: .tcp, on: port)
        } catch {
            LogStore.shared.log("[logserver] start failed: \(error)", level: .error)
            return
        }
        listener.newConnectionHandler = { conn in
            handle(conn)
        }
        listener.stateUpdateHandler = { state in
            if case .failed(let err) = state {
                LogStore.shared.log("[logserver] failed: \(err)", level: .error)
            }
        }
        listener.start(queue: .global(qos: .utility))
        listeners.append(listener)
        LogStore.shared.log("[logserver] up, local IP: \(localIP() ?? "unknown")")
    }

    /// Best-effort LAN IPv4 (en0/awdl0).
    static func localIP() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let interface = ptr.pointee
            let addrFamily = interface.ifa_addr.pointee.sa_family
            if addrFamily == UInt8(AF_INET) || addrFamily == UInt8(AF_INET6) {
                let name = String(cString: interface.ifa_name)
                if name == "en0" || name == "awdl0" {
                    var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    if getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                                   &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                        address = String(cString: host)
                        if address?.contains(":") == false { break }
                    }
                }
            }
        }
        return address
    }

    // MARK: - Private

    private static var listeners: [NWListener] = []

    private static func handle(_ conn: NWConnection) {
        conn.start(queue: .global(qos: .utility))
        let acc = RequestAccumulator()
        receiveLoop(conn, acc)
    }

    /// Accumulates headers + body, then hands the full request to respond().
    private static func receiveLoop(_ conn: NWConnection, _ acc: RequestAccumulator) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
            if let data, !data.isEmpty { acc.data.append(data) }

            if error != nil, acc.data.isEmpty { conn.cancel(); return }

            if acc.headerEnd == nil,
               let r = search(acc.data, Data("\r\n\r\n".utf8)) {
                acc.headerEnd = r
                if acc.contentLength == 0, let hdr = String(data: acc.data[..<r], encoding: .utf8) {
                    acc.contentLength = contentLength(from: hdr)
                }
            }

            let done: Bool
            if let h = acc.headerEnd {
                done = acc.data.count >= h + acc.contentLength
            } else {
                done = false
            }

            if done || isComplete {
                respond(conn, acc)
            } else {
                receiveLoop(conn, acc)
            }
        }
    }

    private static func respond(_ conn: NWConnection, _ acc: RequestAccumulator) {
        let full = String(data: acc.data, encoding: .utf8) ?? ""
        let lines = full.components(separatedBy: "\r\n")
        let requestLine = lines.first ?? ""
        let parts = requestLine.split(separator: " ").map(String.init)
        let method = parts.first ?? "GET"
        let path = parts.count > 1 ? parts[1] : "/"
        let body: String
        if let h = acc.headerEnd {
            body = String(data: acc.data.dropFirst(h + 4), encoding: .utf8) ?? ""
        } else {
            body = ""
        }

        var (status, contentType, payload): (String, String, String)
        if method == "POST" && path == "/action" {
            (status, contentType, payload) = RemoteConsole.handleAction(body: body)
        } else if method == "GET" {
            (status, contentType, payload) = route(path)
        } else {
            (status, contentType, payload) = ("404 Not Found", "text/plain", "not found")
        }

        let http = "HTTP/1.1 \(status)\r\n" +
            "Content-Type: \(contentType)\r\n" +
            "Content-Length: \(payload.utf8.count)\r\n" +
            "Connection: close\r\n" +
            "\r\n" + payload
        conn.send(content: http.data(using: .utf8), completion: .contentProcessed { _ in
            conn.cancel()
        })
    }

    private static func route(_ path: String) -> (String, String, String) {
        switch path {
        case "/log":
            return ok(read(LogStore.logFileURL), "text/plain; charset=utf-8")
        case "/wine":
            let w = LogStore.logFileURL.deletingLastPathComponent().appendingPathComponent("madeira-log.txt")
            return ok(read(w), "text/plain; charset=utf-8")
        case "/srv":
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            let p = docs?.appendingPathComponent("madeira-log.txt")
            return ok(p.map(read) ?? "", "text/plain; charset=utf-8")
        case "/crash":
            return ok(read(CrashCatcher.logURL), "text/plain; charset=utf-8")
        case "/all":
            let l = read(LogStore.logFileURL)
            let caches = LogStore.logFileURL.deletingLastPathComponent().appendingPathComponent("madeira-log.txt")
            let w = read(caches)
            var s = ""
            if let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                s = read(docs.appendingPathComponent("madeira-log.txt"))
            }
            return ok("=== log.txt ===\n\(l)\n\n=== madeira-log.txt (Caches) ===\n\(w)\n\n=== madeira-log.txt (Documents/wineserver) ===\n\(s)", "text/plain; charset=utf-8")
        case "/ip":
            if let ip = localIP() { return ok("{\"ip\": \"\(ip)\"}", "application/json") }
            return ok("{\"ip\": null}", "application/json")
        case "/health":
            return ok("{\"ok\": true}", "application/json")
        case "/jit":
            Task { @MainActor in SteamTVLibrary.shared.rearmJIT() }
            let off = fex_get_jit_write_offset()
            return ok("{\"jit\": \(off != 0), \"offset\": \(off)}", "application/json")
        case "/jitstatus":
            let off = fex_get_jit_write_offset()
            return ok("{\"jit\": \(off != 0), \"offset\": \(off)}", "application/json")
        case "/status":
            return ok(RemoteConsole.statusJSON(), "application/json; charset=utf-8")
        case "/routes":
            return ok(RemoteConsole.routesJSON(), "application/json; charset=utf-8")
        case "/journal":
            return ok(LaunchJournal.shared.jsonString(), "application/json; charset=utf-8")
        case "/panel":
            return ok(RemoteConsole.panelHTML, "text/html; charset=utf-8")
        default:
            return ("404 Not Found", "text/plain", "not found")
        }
    }

    private static func ok(_ body: String, _ type: String) -> (String, String, String) {
        ("200 OK", type, body)
    }

    private static func contentLength(from header: String) -> Int {
        for line in header.components(separatedBy: "\r\n") {
            let low = line.lowercased()
            if low.hasPrefix("content-length:") {
                let v = line.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)
                return Int(v) ?? 0
            }
        }
        return 0
    }

    private static func search(_ haystack: Data, _ needle: Data) -> Int? {
        guard needle.count > 0, haystack.count >= needle.count else { return nil }
        return haystack.range(of: needle)?.lowerBound
    }

    static func read(_ url: URL) -> String {
        (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    /// Tail of a file, last `maxLines` non-empty lines.
    static func tail(_ url: URL?, maxLines: Int) -> [String] {
        guard let url else { return [] }
        let all = read(url).split(separator: "\n").map(String.init)
        guard all.count > 0 else { return [] }
        return Array(all.suffix(maxLines))
    }
}

/// State for one in-flight connection's request read.
private final class RequestAccumulator {
    var data = Data()
    var headerEnd: Int?
    var contentLength = 0
}