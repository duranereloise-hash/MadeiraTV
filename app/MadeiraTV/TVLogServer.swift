// SPDX-License-Identifier: GPL-3.0-or-later
// Madeira Converter Exception: see LICENSE-EXCEPTION.md
//
// Minimal HTTP server on the Apple TV that serves the log files over the
// local network, so the AI assistant (or the user from a PC) can pull logs
// without extra tooling:
//
//   GET /log          -> Library/Caches/log.txt
//   GET /wine         -> Library/Caches/madeira-log.txt
//   GET /all          -> both, concatenated
//   GET /ip           -> JSON { "ip": "..." }
//   GET /health       -> JSON { "ok": true }
//
// Runs on port 9090, bound to 0.0.0.0. No permission prompt is needed to
// *listen*; the incoming connection is accepted by the app process.

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
        // Store it so the listener stays alive for the app lifetime.
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
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, _ in
            defer { conn.cancel() }
            guard let data, let text = String(data: data, encoding: .utf8) else { return }
            let requestLine = text.components(separatedBy: "\r\n").first ?? ""
            let path = requestLine.split(separator: " ").dropFirst().first.map(String.init) ?? "/"
            let (body, contentType) = route(path)
            let http = """
            HTTP/1.1 200 OK\r
            Content-Type: \(contentType)\r
            Content-Length: \(body.utf8.count)\r
            Connection: close\r
            \r
            \(body)
            """
            conn.send(content: http.data(using: .utf8), completion: .contentProcessed { _ in })
            _ = isComplete
        }
    }

    private static func route(_ path: String) -> (String, String) {
        switch path {
        case "/log":
            return (read(LogStore.logFileURL), "text/plain; charset=utf-8")
        case "/wine":
            let w = LogStore.logFileURL.deletingLastPathComponent().appendingPathComponent("madeira-log.txt")
            return (read(w), "text/plain; charset=utf-8")
        case "/all":
            let l = read(LogStore.logFileURL)
            let w = read(LogStore.logFileURL.deletingLastPathComponent().appendingPathComponent("madeira-log.txt"))
            return ("=== log.txt ===\n\(l)\n\n=== madeira-log.txt ===\n\(w)", "text/plain; charset=utf-8")
        case "/ip":
            if let ip = localIP() {
                return ("{\"ip\": \"\(ip)\"}", "application/json")
            }
            return ("{\"ip\": null}", "application/json")
        case "/health":
            return ("{\"ok\": true}", "application/json")
        default:
            return ("not found", "text/plain")
        }
    }

    private static func read(_ url: URL) -> String {
        (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }
}