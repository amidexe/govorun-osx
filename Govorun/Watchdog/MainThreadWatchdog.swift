import Foundation
import AppKit

/// Сторож главного потока.
///
/// Если UI завис — главный поток не отвечает дольше `timeout` — приложение
/// самозавершается, чтобы зацикленная раскладка SwiftUI или любой другой клин
/// не жгли CPU и батарею часами незаметно для пользователя.
///
/// Предыстория (инцидент 2026-06): бесконечный layout-loop в окне «Настройки»
/// (`Form`/`TabView`) держал главный поток на 99% CPU около 7 часов. Кнопки не
/// нажимались (события не доходили до занятого main-потока), ноутбук грелся,
/// батарея садилась. Сторож гарантирует выход независимо от первопричины —
/// это страховка, а не лечение конкретного бага SwiftUI.
///
/// Важно: следим ТОЛЬКО за главным потоком. Тяжёлая транскрипция уходит в
/// `Task.detached` (см. `GigaAMEngine`), поэтому распознавание сторож не трогает.
final class MainThreadWatchdog {
    static let shared = MainThreadWatchdog()

    private let queue = DispatchQueue(label: "com.govorun.watchdog", qos: .utility)
    private let pingInterval: TimeInterval
    private let timeout: TimeInterval
    private let startupGrace: TimeInterval

    private let lock = NSLock()
    private var lastResponse = Date()
    private var startedAt = Date()
    private var timer: DispatchSourceTimer?

    /// - timeout: сколько главный поток может молчать, прежде чем считать UI
    ///   зависшим. Щедро (30 c), чтобы не убить приложение из-за короткой
    ///   легитимной загрузки (модель, модальные окна).
    /// - startupGrace: на старте загрузка модели и инициализация могут коротко
    ///   занять main — не проверяем первые `startupGrace` секунд.
    init(pingInterval: TimeInterval = 3, timeout: TimeInterval = 30, startupGrace: TimeInterval = 15) {
        self.pingInterval = pingInterval
        self.timeout = timeout
        self.startupGrace = startupGrace
    }

    func start() {
        guard timer == nil else { return }
        startedAt = Date()
        markResponsive()
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + pingInterval, repeating: pingInterval)
        t.setEventHandler { [weak self] in self?.tick() }
        timer = t
        t.resume()
        runSelfTestIfRequested()
    }

    private func tick() {
        // Пинг главного потока: если он жив, обработает блок и обновит метку.
        // Если завис — блок не выполнится, метка устареет, сторож сработает.
        DispatchQueue.main.async { [weak self] in self?.markResponsive() }

        // Грейс на старте — пропускаем ранние проверки.
        guard Date().timeIntervalSince(startedAt) > startupGrace else { return }

        lock.lock(); let last = lastResponse; lock.unlock()
        let stalled = Date().timeIntervalSince(last)
        if stalled >= timeout {
            NSLog("‼️ [Watchdog] Главный поток не отвечает %.0f c — самозавершаюсь, чтобы не жечь CPU/батарею.", stalled)
            // NSApp.terminate(_:) бесполезен — ему нужен живой главный поток.
            // Выходим жёстко из фонового потока сторожа.
            exit(0)
        }
    }

    private func markResponsive() {
        lock.lock(); lastResponse = Date(); lock.unlock()
    }

    // MARK: - Самопроверка
    // Только Debug + явная переменная окружения. Для пользователя дремлет:
    // переменная не выставлена → никакого намеренного зависания не происходит.
    private func runSelfTestIfRequested() {
        #if DEBUG
        guard ProcessInfo.processInfo.environment["GOVORUN_WATCHDOG_SELFTEST"] == "1" else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + startupGrace + 1) {
            NSLog("🧪 [Watchdog] SELFTEST: блокирую главный поток — ожидается самозавершение через ~%.0f c.", self.timeout)
            Thread.sleep(forTimeInterval: 600)   // имитация зависшего UI
        }
        #endif
    }
}
