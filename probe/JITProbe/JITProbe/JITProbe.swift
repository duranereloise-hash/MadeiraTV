import Foundation
import Darwin

/// Swift shim around the C-core matrix runner (JITProbeCore.c).
/// Reads the report buffer produced by jitprobe_run_matrix, prints it, and
/// serves it on :9091.
@objcMembers
final class JITProbe: NSObject {
    static var onUpdate: ((String) -> Void)?

    @_silgen_name("jitprobe_run_matrix")
    private static func jitprobe_run_matrix(_ out: UnsafeMutablePointer<CChar>, _ outsz: Int) -> Int32

    @_silgen_name("jitprobe_compile_flags")
    private static func jitprobe_compile_flags() -> Int32

    @_silgen_name("jitprobe_open_partial")
    private static func jitprobe_open_partial(_ path: UnsafePointer<CChar>)

    static func run() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let partialPath = caches.appendingPathComponent("jitprobe-partial.log")
        // Open the appends-only partial file BEFORE running the matrix so a
        // mid-matrix SIGKILL still leaves the completed prefix on disk.
        let pp = (partialPath.path as NSString).fileSystemRepresentation
        jitprobe_open_partial(pp)

        // Start the HTTP server FIRST so the partial log is readable even if
        // the process dies on the very first test. Each request re-reads the
        // file, so a re-opened app serves the surviving prefix.
        partialURL = partialPath
        startHTTPServer()

        var report = "JITProbe v2 — matrix, \(Date())\n"
        let flags = jitprobe_compile_flags()
        let cs = flags < 0 ? -1 : Int(flags)
        if cs >= 0 {
            let f = UInt32(cs)
            report += "codeSigningFlags=0x\(String(f, radix: 16)) "
            report += "CS_DEBUGGED=\( (f & 0x10000000) != 0 ) CS_RUNTIME=\( (f & 0x20000000) != 0 ) "
            report += "GET_TASK_ALLOW=\( (f & 0x4) != 0 ) HARD=\( (f & 0x100) != 0 ) KILL=\( (f & 0x200) != 0 )\n"
        } else {
            report += "csops failed rc=\(flags)\n"
        }

        let buf = UnsafeMutablePointer<CChar>.allocate(capacity: 16384)
        defer { buf.deallocate() }
        let rc = jitprobe_run_matrix(buf, 16384)
        if rc == 0 {
            report += String(cString: buf)
        } else {
            report += "jitprobe_run_matrix returned \(rc)\n"
        }
        report += "\n== partial loopback ==\n"
        if let pr = try? String(contentsOf: partialPath, encoding: .utf8) {
            report += pr
        }
        report += "\n== device ==\n" + deviceInfo() + "\n"

        // stash report for HTTP
        lastReport = report
        writeLog(report)
        startHTTPServer()
        onUpdate?(report)
        print(report)
    }

    private static var lastReport = ""
    private static var serverUp = false
    private static var partialURL: URL?

    private static func deviceInfo() -> String {
        var size = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        var machine = [CChar](repeating: 0, count: Int(size))
        sysctlbyname("hw.machine", &machine, &size, nil, 0)
        let osv = ProcessInfo.processInfo.operatingSystemVersionString
        return "\(String(cString: machine)) \(osv)"
    }

    private static func writeLog(_ text: String) {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let url = docs.appendingPathComponent("jitprobe.log")
        try? text.write(to: url, atomically: true, encoding: .utf8)
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        try? text.write(to: caches.appendingPathComponent("jitprobe.log"), atomically: true, encoding: .utf8)
        print("[JITProbe] wrote \(url.path)")
    }

    // MARK: - Tiny HTTP :9091

    private static func startHTTPServer() {
        if serverUp { return }
        serverUp = true
        DispatchQueue.global(qos: .utility).async {
            let fd = socket(AF_INET, SOCK_STREAM, 0)
            var opt: Int32 = 1
            setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &opt, socklen_t(MemoryLayout<Int32>.size))
            var addr = sockaddr_in()
            addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_port = (9091 as UInt16).bigEndian
            addr.sin_addr.s_addr = INADDR_ANY
            let bindR = withUnsafePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            guard bindR == 0 else { print("[JITProbe] bind failed errno=\(errno)"); return }
            listen(fd, 4)
            while true {
                let c = accept(fd, nil, nil)
                if c < 0 { continue }
                // Serve: live partial log + last completed report buffer.
                var body = lastReport
                if let p = partialURL, let pr = try? String(contentsOf: p, encoding: .utf8), !pr.isEmpty {
                    body = "=== LIVE PARTIAL LOG ===\n\(pr)\n=== BUFFER ===\n\(body)"
                }
                let resp = "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
                _ = resp.withCString { write(c, $0, resp.utf8.count) }
                close(c)
            }
        }
    }
}