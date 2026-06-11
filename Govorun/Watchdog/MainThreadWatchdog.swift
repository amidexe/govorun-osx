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

    private enum TickOutcome {
        case alive
        case startupGrace
        case resetAfterTimerSuspension(TimeInterval)
        case mainThreadStalled(TimeInterval)
    }

    private let queue = DispatchQueue(label: "com.govorun.watchdog", qos: .utility)
    private let pingInterval: TimeInterval
    private let timeout: TimeInterval
    private let startupGrace: TimeInterval

    private let lock = NSLock()
    private var lastResponse = Date()
    private var lastTick = Date()
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
        lastTick = startedAt
        markResponsive()
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + pingInterval, repeating: pingInterval)
        t.setEventHandler { [weak self] in self?.tick() }
        timer = t
        t.resume()
        runSelfTestIfRequested()
    }

    @discardableResult
    private func tick(
        now: Date = Date(),
        exitOnStall: Bool = true,
        recordDiagnostics: Bool = true
    ) -> TickOutcome {
        lock.lock()
        let previousTick = lastTick
        lastTick = now
        let last = lastResponse
        lock.unlock()

        let timerGap = now.timeIntervalSince(previousTick)
        if timerGap > timeout {
            resetAfterTimerSuspension(timerGap, recordDiagnostics: recordDiagnostics)
            return .resetAfterTimerSuspension(timerGap)
        }

        // Пинг главного потока: если он жив, обработает блок и обновит метку.
        // Если завис — блок не выполнится, метка устареет, сторож сработает.
        DispatchQueue.main.async { [weak self] in self?.markResponsive() }

        // Грейс на старте — пропускаем ранние проверки.
        guard now.timeIntervalSince(startedAt) > startupGrace else { return .startupGrace }

        let stalled = now.timeIntervalSince(last)
        if stalled >= timeout {
            if recordDiagnostics {
                NSLog("‼️ [Watchdog] Главный поток не отвечает %.0f c — самозавершаюсь, чтобы не жечь CPU/батарею.", stalled)
                DiagnosticsLog.record(
                    "Watchdog завершает приложение: главный поток не отвечает \(Int(stalled)) с.",
                    category: "Приложение",
                    level: .error
                )
            }
            // NSApp.terminate(_:) бесполезен — ему нужен живой главный поток.
            // Выходим жёстко из фонового потока сторожа.
            if exitOnStall {
                exit(0)
            }
            return .mainThreadStalled(stalled)
        }
        return .alive
    }

    private func resetAfterTimerSuspension(_ gap: TimeInterval, recordDiagnostics: Bool = true) {
        lock.lock()
        lastResponse = Date()
        startedAt = Date()
        lock.unlock()
        if recordDiagnostics {
            NSLog("ℹ️ [Watchdog] Таймер возобновился после паузы %.0f c — считаю это sleep/wake и сбрасываю сторож.", gap)
            DiagnosticsLog.record(
                "Watchdog сброшен после сна или паузы таймера: \(Int(gap)) с.",
                category: "Приложение"
            )
        }
    }

    private func markResponsive() {
        lock.lock(); lastResponse = Date(); lock.unlock()
    }

    static func runSleepWakeSelfTestIfRequested() {
        guard ProcessInfo.processInfo.environment["GOVORUN_WATCHDOG_SLEEP_SELFTEST"] == "1" else { return }

        func fail(_ message: String) -> Never {
            fputs("watchdog sleep/wake regression failed: \(message)\n", stderr)
            exit(1)
        }

        let timeout: TimeInterval = 30
        let now = Date()
        let sleepWakeWatchdog = MainThreadWatchdog(pingInterval: 3, timeout: timeout, startupGrace: 0)
        sleepWakeWatchdog.lock.lock()
        sleepWakeWatchdog.lastTick = now.addingTimeInterval(-(timeout + 90))
        sleepWakeWatchdog.lastResponse = now.addingTimeInterval(-(timeout + 90))
        sleepWakeWatchdog.startedAt = now.addingTimeInterval(-(timeout + 90))
        sleepWakeWatchdog.lock.unlock()

        switch sleepWakeWatchdog.tick(now: now, exitOnStall: false, recordDiagnostics: false) {
        case .resetAfterTimerSuspension:
            break
        case .mainThreadStalled:
            fail("sleep/wake timer suspension was treated as a main-thread stall")
        default:
            fail("sleep/wake timer suspension was not reset")
        }

        let stalledWatchdog = MainThreadWatchdog(pingInterval: 3, timeout: timeout, startupGrace: 0)
        stalledWatchdog.lock.lock()
        stalledWatchdog.lastTick = now.addingTimeInterval(-3)
        stalledWatchdog.lastResponse = now.addingTimeInterval(-(timeout + 5))
        stalledWatchdog.startedAt = now.addingTimeInterval(-(timeout + 5))
        stalledWatchdog.lock.unlock()

        switch stalledWatchdog.tick(now: now, exitOnStall: false, recordDiagnostics: false) {
        case .mainThreadStalled:
            print("watchdog sleep/wake regression checks: ok")
            exit(0)
        case .resetAfterTimerSuspension:
            fail("real main-thread stall was incorrectly treated as sleep/wake")
        default:
            fail("real main-thread stall was not detected")
        }
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
