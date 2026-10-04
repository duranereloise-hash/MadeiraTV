import SwiftUI
import GameController

@main
struct MadeiraTVApp: App {
    @StateObject private var steam = SteamTVLibrary.shared

    var body: some Scene {
        WindowGroup {
            TVHomeView()
                .environmentObject(steam)
                .onAppear {
                    GameControllerNotificationObserver.shared.start()
                    steam.start()
                }
        }
    }
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