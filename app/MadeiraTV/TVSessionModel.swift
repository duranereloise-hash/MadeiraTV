import SwiftUI
import Combine

/// Фаза 1 tvOS-порт: лёгкая модель без привязки к Wine/FEX/DXMT.
/// Полный запуск Windows-игр подключается на Фазе 2 (сборка Wine под tvOS).
final class TVSessionModel: ObservableObject {
    static let shared = TVSessionModel()
    @Published var running = false
    @Published var message = ""

    func startDemo() {
        message = "Демо-сессия запущена. На Фазе 2 здесь будет Wine + FEX."
        running = true
    }

    func stop() {
        running = false
    }
}