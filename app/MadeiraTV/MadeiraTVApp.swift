import SwiftUI
import GameController
import Darwin

@main
struct MadeiraTVApp: App {
    @StateObject private var steam = SteamTVLibrary.shared

    init() {
        CrashCatcher.install()
    }

    var body: some Scene {
        WindowGroup {
            TVHomeView()
                .environmentObject(steam)
                .onAppear {
                    GameControllerNotificationObserver.shared.start()
                    steam.start()
                    TVLogServer.start()
                }
        }
    }
}

/// Minimal crash logger: writes an ObjC-exception/Unix-signal death note to
/// Library/Caches/crash.log (always writable on tvOS) so a hard kill (e.g.
/// the 5-7s crash after Play) leaves a breadcrumb the TVLogServer can serve.
enum CrashCatcher {
    static let logURL: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("crash.log")
    }()

    static func install() {
        NSSetUncaughtExceptionHandler { exception in
            let desc = "\(exception.name) \(exception.reason ?? "")"
            CrashCatcher.write("[NSException] \(desc)")
            CrashCatcher.write(exception.callStackSymbols.joined(separator: "\n"))
        }
        let sigs: [Int32] = [SIGABRT, SIGBUS, SIGFPE, SIGILL, SIGSEGV, SIGTRAP, SIGSYS]
        for s in sigs {
            signal(s, crashSignalHandler)
        }
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
}

private func crashSignalHandler(_ sig: Int32) {
    CrashCatcher.write("[signal] \(sig)")
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