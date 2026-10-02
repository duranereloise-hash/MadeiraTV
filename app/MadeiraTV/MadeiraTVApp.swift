import SwiftUI
import GameController

@main
struct MadeiraTVApp: App {
    @StateObject private var session = TVSessionModel.shared

    var body: some Scene {
        WindowGroup {
            TVContentView()
                .environmentObject(session)
                .onAppear {
                    GameControllerNotificationObserver.shared.start()
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

struct TVContentView: View {
    @EnvironmentObject private var session: TVSessionModel

    var body: some View {
        NavigationStack {
            if session.running {
                TVSessionView()
            } else {
                TVLibraryView()
            }
        }
    }
}

struct TVLibraryView: View {
    @EnvironmentObject private var session: TVSessionModel

    var body: some View {
        VStack(spacing: 28) {
            Image(systemName: "tv")
                .font(.system(size: 72))
                .foregroundStyle(.tint)
            Text("Madeira for tvOS")
                .font(.largeTitle.bold())
            Text("Windows PC-игры на Apple TV через Wine + FEX-Emu + DXMT")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 60)
            Button {
                session.startDemo()
            } label: {
                Label("Демо-сессия", systemImage: "play.fill")
                    .font(.title3.bold())
                    .padding(.horizontal, 48)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 16)
        }
        .padding()
    }
}

struct TVSessionView: View {
    @EnvironmentObject private var session: TVSessionModel

    var body: some View {
        VStack(spacing: 24) {
            Text("Сессия запущена")
                .font(.largeTitle.bold())
            Text(session.message)
                .font(.title3)
                .foregroundStyle(.secondary)
            Button {
                session.stop()
            } label: {
                Label("Выйти", systemImage: "xmark.circle")
                    .font(.title3.bold())
            }
            .buttonStyle(.bordered)
        }
    }
}