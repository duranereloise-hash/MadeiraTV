import SwiftUI
import Combine

/// tvOS minimal session: starts the real Wine server + a Wine process
/// (default demo exe = cube.exe) on a background thread and reports progress.
final class TVSessionModel: ObservableObject {
    static let shared = TVSessionModel()
    @Published var running = false
    @Published var message = ""

    private let queue = DispatchQueue(label: "tv.wine.bootstrap", qos: .userInitiated)

    func startDemo() {
        guard !running else { return }
        running = true
        message = "Старт Wine..."

        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let prefixPath = documents.appendingPathComponent("wine").path

        queue.async { [weak self] in
            guard let self = self else { return }
            self.dispatch("Prefix: \(prefixPath)")

            let ws = wineserver_start(prefixPath)
            if ws != 0 {
                self.dispatch("Ошибка wineserver (\(ws))")
                self.running = false
                return
            }
            self.dispatch("Wineserver запущен")

            // Give the server thread a moment to init, then launch the guest.
            Thread.sleep(forTimeInterval: 1.0)

            if wineserver_is_running() == 0 {
                self.dispatch("Wineserver не готов")
                self.running = false
                return
            }

            let wp = wine_process_start(prefixPath)
            if wp != 0 {
                self.dispatch("Ошибка Wine-процесса (\(wp))")
                self.running = false
                return
            }
            self.dispatch("Сессия запущена: Wine + FEX (cube.exe)")
        }
    }

    func stop() {
        queue.async { [weak self] in
            wineserver_stop()
            DispatchQueue.main.async {
                self?.running = false
                self?.message = "Сессия остановлена"
            }
        }
    }

    private func dispatch(_ text: String) {
        DispatchQueue.main.async { [weak self] in
            self?.message = text
        }
    }
}