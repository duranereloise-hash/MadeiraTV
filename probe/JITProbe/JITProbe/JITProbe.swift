import Foundation
import Darwin
import MachO
import MachO.arm

/// Minimal self-contained JIT probe for tvOS 27 / free-provisioning.
/// Tests in order:
///  1) csops CS_DEBUGGED + code-signing flags
///  2) MAP_JIT mmap(EXEC) — does it succeed? does exec work?
///  3) MeloNX-style mach shared-memory dual-map — does exec work?
/// Writes a log to Documents/jitprobe.log and exposes it over a tiny HTTP
/// server on :9091 so it can be read from a PC without the app UI.
@objcMembers
final class JITProbe: NSObject {
    static var onUpdate: ((String) -> Void)?
    private static var logLines: [String] = []

    static func run() {
        var report = "=== JITProbe tvOS27 \(Date()) ===\n"
        append("device=\(deviceInfo())")

        // 1) Signing status
        let flags = codeSigningFlags()
        report += "codeSigningFlags=0x\(String(flags, radix: 16)) CS_DEBUGGED=\((flags & 0x10000000) != 0) CS_RUNTIME=\((flags & 0x20000000) != 0)\n"
        append("codeSigningFlags=0x\(String(flags, radix: 16))")

        // 2) MAP_JIT probe
        report += "=== MAP_JIT ===\n"
        let mapJit = probeMapJit()
        report += mapJit
        append("mapJit: \(mapJit.replacingOccurrences(of: "\n", with: " | "))")

        // 3) MeloNX dual-map probe
        report += "=== MeloNX ===\n"
        let melo = probeMeloNX()
        report += melo
        append("meloNX: \(melo.replacingOccurrences(of: "\n", with: " | "))")

        // 4) pthread_jit_write_protect availability
        report += "=== jit-write-protect ===\n"
        let jwp = probeJitWriteProtect()
        report += jwp
        append("jitWriteProtect: \(jwp.replacingOccurrences(of: "\n", with: " | "))")

        report += "=== DONE ===\n"
        writeLog(report)
        startHTTPServer()
        onUpdate?(report)
    }

    // MARK: - Probes

    private static func probeMapJit() -> String {
        let size = 16 * 1024
        let ptr = mmap(nil, size, PROT_READ | PROT_WRITE | PROT_EXEC,
                       MAP_ANON | MAP_PRIVATE | MAP_JIT, -1, 0)
        guard ptr != MAP_FAILED else {
            return "mmap(MAP_JIT) FAILED errno=\(errno) — MAP_JIT blocked\n"
        }
        defer { munmap(ptr, size) }
        let addr = UInt(bitPattern: ptr)
        guard execProbe(ptr) else {
            return "mmap(MAP_JIT) OK at 0x\(String(addr, radix: 16)) but EXEC FAILED (SIGSEGV/SIGBUS or no-op) — TXM/AMFI kills it\n"
        }
        return "mmap(MAP_JIT) OK at 0x\(String(addr, radix: 16)) + EXEC OK — JIT WORKS via MAP_JIT!\n"
    }

    private static func probeMeloNX() -> String {
        let size = 16 * 1024
        var entry: mach_port_t = 0
        var entrySize: memory_object_size_t = memory_object_size_t(size)
        let task = mach_task_self_
        var kr = mach_make_memory_entry_64(task, &entrySize, 0,
                                           MAP_MEM_NAMED_CREATE | VM_PROT_READ | VM_PROT_WRITE | VM_PROT_EXECUTE,
                                           &entry, 0)
        guard kr == KERN_SUCCESS else {
            return "mach_make_memory_entry_64 FAILED kr=\(kr)\n"
        }
        defer { mach_port_deallocate(task, entry) }

        var rwAddr: mach_vm_address_t = 0
        kr = vm_map(task, &rwAddr, size, 0, VM_FLAGS_ANYWHERE, entry, 0, false,
                    VM_PROT_READ | VM_PROT_WRITE, VM_PROT_READ | VM_PROT_WRITE | VM_PROT_EXECUTE,
                    VM_INHERIT_DEFAULT)
        guard kr == KERN_SUCCESS else {
            return "vm_map RW FAILED kr=\(kr)\n"
        }

        var rxAddr: mach_vm_address_t = 0
        kr = vm_map(task, &rxAddr, size, 0, VM_FLAGS_ANYWHERE, entry, 0, false,
                    VM_PROT_READ | VM_PROT_EXECUTE, VM_PROT_READ | VM_PROT_WRITE | VM_PROT_EXECUTE,
                    VM_INHERIT_DEFAULT)
        guard kr == KERN_SUCCESS else {
            return "vm_map RX FAILED kr=\(kr)\n"
        }

        let rw = UnsafeMutableRawPointer(bitPattern: UInt(rwAddr))!
        let rx = UnsafeMutableRawPointer(bitPattern: UInt(rxAddr))!
        guard execProbe(at: rw, execPtr: rx) else {
            return "MeloNX dual-map OK (RW=0x\(String(rwAddr, radix: 16)) RX=0x\(String(rxAddr, radix: 16))) but EXEC FAILED — TXM kills SM=SHM\n"
        }
        return "MeloNX dual-map OK + EXEC OK — JIT WORKS via MeloNX!\n"
    }

    private static func probeJitWriteProtect() -> String {
        // pthread_jit_write_protect_np isn't in tvOS public headers; dlsym it.
        guard let fn = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "pthread_jit_write_protect_np") else {
            return "pthread_jit_write_protect_np NOT AVAILABLE\n"
        }
        typealias JWP = @convention(c) (Int32) -> Void
        let jwp = unsafeBitCast(fn, to: JWP.self)
        jwp(0) // allow writes
        jwp(1) // protect again
        return "pthread_jit_write_protect_np AVAILABLE (callable ok)\n"
    }

    // MARK: - Exec probe

    /// Writes a tiny ARM64 function: `ret` (0xD65F03C0) into `writePtr`,
    /// executes it via `execPtr`, returns true if it ran.
    private static func execProbe(_ ptr: UnsafeMutableRawPointer) -> Bool {
        execProbe(at: ptr, execPtr: ptr)
    }

    private static func execProbe(at writePtr: UnsafeMutableRawPointer,
                                  execPtr: UnsafeMutableRawPointer) -> Bool {
        // mov x0, #0x2A ; ret  =>  d2800540  d65f03c0
        let mov: UInt32 = 0xD2800540  // mov x0, #42
        let ret: UInt32 = 0xD65F03C0  // ret
        writePtr.storeBytes(of: mov, as: UInt32.self)
        writePtr.advanced(by: 4).storeBytes(of: ret, as: UInt32.self)
        sys_icache_invalidate(execPtr, 8)

        // Call through a function pointer; catch faults.
        let fn = unsafeBitCast(execPtr, to: (@convention(c) () -> UInt64).self)
        var crash = false
        signal(SIGSEGV) { _ in crash = true }
        signal(SIGBUS) { _ in crash = true }
        var result: UInt64 = 0
        if !crash {
            result = fn()
        }
        signal(SIGSEGV, SIG_DFL)
        signal(SIGBUS, SIG_DFL)
        return !crash && result == 42
    }

    // MARK: - Helpers

    private static func codeSigningFlags() -> UInt32 {
        var flags: UInt32 = 0
        // csops(CS_OPS_STATUS=0)
        let r = csops_wrap(getpid(), 0, &flags, 4)
        if r == 0 { return flags }
        return 0
    }

    // csops is a kernel syscall; declare it (not in tvOS SDK).
    private typealias csops_fn = @convention(c) (pid_t, UInt32, UnsafeMutableRawPointer, Int) -> Int32
    private static let csopsSym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "csops")
    private static func csops_wrap(_ pid: pid_t, _ op: UInt32, _ addr: UnsafeMutableRawPointer, _ size: Int) -> Int32 {
        guard let sym = csopsSym else { return -1 }
        let f = unsafeBitCast(sym, to: csops_fn.self)
        return f(pid, op, addr, size)
    }

    private static func deviceInfo() -> String {
        var size = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        var machine = [CChar](repeating: 0, count: Int(size))
        sysctlbyname("hw.machine", &machine, &size, nil, 0)
        let osv = ProcessInfo.processInfo.operatingSystemVersionString
        return "\(String(cString: machine)) \(osv)"
    }

    private static func append(_ s: String) {
        logLines.append(s)
        print("[JITProbe] \(s)")
    }

    private static func writeLog(_ text: String) {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let url = docs.appendingPathComponent("jitprobe.log")
        try? text.write(to: url, atomically: true, encoding: .utf8)
        print("[JITProbe] wrote \(url.path)")
    }

    // MARK: - Tiny HTTP server (:9091)

    private static func startHTTPServer() {
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
            let body = logLines.joined(separator: "\n")
            while true {
                let c = accept(fd, nil, nil)
                if c < 0 { continue }
                let resp = "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
                _ = resp.withCString { write(c, $0, resp.utf8.count) }
                close(c)
            }
        }
    }
}