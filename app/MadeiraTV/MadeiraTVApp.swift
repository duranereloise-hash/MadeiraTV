import SwiftUI
import GameController
import Darwin

@main
struct MadeiraTVApp: App {
    @StateObject private var steam = SteamTVLibrary.shared

    init() {
        // ml1197f: keep the signal/exception handler in Release too — a tvOS
        // CODESIGNING SIGKILL happens outside any #if DEBUG check window, and
        // without the handler the last lines before a crash are never written.
        // Also snapshot any pre-existing crash.log so the tail from the run
        // that died survives the next install/relaunch.
        CrashCatcher.backupIfPresent()
        CrashCatcher.install()
    }

    var body: some Scene {
        WindowGroup {
            TVRootView()
                .installSharedEnvironment()
                .onAppear {
                    GameControllerNotificationObserver.shared.start()
                    steam.start()
                    TVLogServer.start()
                }
        }
    }
}

/// Minimal crash logger: writes an ObjC-exception/Unix-signal death note plus
/// a backtrace to Library/Caches/crash.log (always writable on tvOS) so a hard
/// kill (e.g. the 5-7s crash after Play) leaves a breadcrumb the TVLogServer
/// can serve.
enum CrashCatcher {
    static let logURL: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("crash.log")
    }()

    static func install() {
        CrashCatcher.write("[boot] MadeiraTV started pid=\(getpid())")
        NSSetUncaughtExceptionHandler { exception in
            let desc = "\(exception.name) \(exception.reason ?? "")"
            CrashCatcher.write("[NSException] \(desc)")
            CrashCatcher.write("-- stack --")
            CrashCatcher.write(exception.callStackSymbols.joined(separator: "\n"))
        }
        let sigs: [Int32] = [SIGABRT, SIGBUS, SIGFPE, SIGILL, SIGSEGV, SIGTRAP, SIGSYS]
        for s in sigs {
            signal(s, crashSignalHandler)
        }
    }

    /// Copy crash.log → crash-<timestamp>.log.bak so the tail of the previous
    /// (crashed) run is never lost when Caches gets cleared or the app resumes.
    static func backupIfPresent() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: logURL.path) else { return }
        let stamp = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .medium)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let back = logURL.deletingLastPathComponent()
            .appendingPathComponent("crash-\(stamp).log.bak")
        try? fm.copyItem(at: logURL, to: back)
        _ = back  // keep path for a log line if needed
    }

    static func write(_ msg: String) {
        let line = "[\(Date())] \(msg)\n"
        if let h = try? FileHandle(forWritingTo: logURL) {
            h.seekToEndOfFile()
            h.write(line.data(using: .utf8) ?? Data())
            try? h.close()
        } else {
            try? line.data(using: .utf8)?.write(to: logURL, options: .atomic)
        }
    }

    static func writeBacktrace() {
        let count = 64
        var callstack = [UnsafeMutableRawPointer?](repeating: nil, count: count)
        let frames = backtrace(&callstack, Int32(count))
        if let syms = backtrace_symbols(&callstack, frames) {
            for i in 0..<Int(frames) {
                if let s = syms[i] { CrashCatcher.write(String(cString: s)) }
            }
        }
    }
}

private func crashSignalHandler(_ sig: Int32) {
    CrashCatcher.write("[signal] \(sig)")
    CrashCatcher.write("-- stack --")
    CrashCatcher.writeBacktrace()
    signal(sig, SIG_DFL)
    raise(sig)
}

/// Minimal GCController observer so gamepads/MFi/Siri Remote are recognised.
final class GameControllerNotificationObserver: NSObject {
    static let shared = GameControllerNotificationObserver()

    func start() {
        _ = GCController.controllers()
        NotificationCenter.default.addObserver(
            forName: .GCControllerDidConnect,
            object: nil, queue: .main
        ) { note in
            if let c = note.object as? GCController {
                print("[tvos] controller connected: \(c.vendorName ?? "unknown")")
            }
        }
        NotificationCenter.default.addObserver(
            forName: .GCControllerDidDisconnect,
            object: nil, queue: .main
        ) { _ in
            print("[tvos] controller disconnected")
        }
    }
}