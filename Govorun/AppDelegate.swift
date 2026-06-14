import AppKit
import SwiftUI
import AVFoundation
import ApplicationServices

// Первый клик сразу срабатывает, не тратится на активацию окна
private class FirstMouseView: NSView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private final class FirstMouseHostingController<V: View>: NSHostingController<V> {
    override func loadView() {
        super.loadView()
        // Оборачиваем hosting view в контейнер, принимающий первый клик
        let container = FirstMouseView()
        container.addSubview(view)
        view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: container.topAnchor),
            view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])
        view = container
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var audioEngine = AudioEngine()
    var hotkeyManager = HotkeyManager()
    private let audioMuter = SystemAudioMuter()
    private var floatingWindowController: FloatingWindowController?
    private var statsPopover:   NSPopover?
    private var autoCloseTask:  Task<Void, Never>?
    private var settingsWindow: NSWindow?
    private var statusItem: NSStatusItem!
    private var permissionCheckTimer: Timer?
    private var permissionStatusTimer: Timer?
    private var lastPermissionAttentionState: Bool?

    private enum RecordingState {
        case idle
        case recording(startedAt: Date)
        case toggleMode(startedAt: Date)
    }
    private var recordingState: RecordingState = .idle
    private let pttThreshold: TimeInterval = 0.35
    // Защищает короткий момент остановки аудиосессии.
    private var isStoppingRecording = false
    private var recognitionTail: Task<Void, Never>?
    private var queuedRecognitionJobs = 0
    // Автостоп по лимиту длительности записи (RecordingOptions.maxRecordingMinutes).
    private var maxDurationTask: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        KeychainSelfTest.runIfRequested()
        OpenAIProxySelfTest.runIfRequested()
        MainThreadWatchdog.runSleepWakeSelfTestIfRequested()
        NSApp.setActivationPolicy(.accessory)
        // Сторож главного потока: если UI зависнет (напр. layout-loop SwiftUI),
        // приложение самозавершится, а не будет жечь CPU/батарею часами.
        MainThreadWatchdog.shared.start()
        RuntimeState.setBusy(false)
        DiagnosticsLog.record("Приложение запущено.", category: "Приложение")
        refreshLLMConfigurationStatus()
        setupMenuBar()
        startPermissionStatusTimer()
        floatingWindowController = FloatingWindowController()
        if !disableHotkeyForSmokeTest {
            setupHotkeyIfTrusted()
        }
        openSettingsForSmokeTestIfNeeded()
    }

    private var disableHotkeyForSmokeTest: Bool {
        ProcessInfo.processInfo.environment["GOVORUN_DISABLE_HOTKEY_ON_LAUNCH"] == "1"
    }

    private func openSettingsForSmokeTestIfNeeded() {
        guard ProcessInfo.processInfo.environment["GOVORUN_OPEN_SETTINGS_ON_LAUNCH"] == "1" else { return }
        DispatchQueue.main.async { [weak self] in
            self?.openSettings()
        }
    }

    // MARK: - Menu bar

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let btn = statusItem.button!
        btn.target = self
        btn.action = #selector(handleStatusBarClick)
        btn.sendAction(on: [.leftMouseUp, .rightMouseUp])
        refreshStatusIcon(force: true)
    }

    @objc private func handleStatusBarClick() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp {
            showContextMenu()
            return
        }
        if let p = statsPopover, p.isShown {
            p.close()
        } else {
            showStatsPopover()
        }
    }

    private func showContextMenu() {
        let menu  = NSMenu()

        let settingsItem = NSMenuItem(title: "Настройки…", action: #selector(openSettings), keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Завершить Говорун", action: #selector(NSApplication.terminate(_:)), keyEquivalent: ""))

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private var missingPermissionNames: [String] {
        var names: [String] = []
        if !AXIsProcessTrusted() {
            names.append("Специальные возможности")
        }
        if AVCaptureDevice.authorizationStatus(for: .audio) != .authorized {
            names.append("Микрофон")
        }
        return names
    }

    private var requiredPermissionsGranted: Bool {
        missingPermissionNames.isEmpty
    }

    private func refreshStatusIcon(force: Bool = false) {
        let missing = missingPermissionNames
        let needsAttention = !missing.isEmpty
        guard force || lastPermissionAttentionState != needsAttention else { return }
        lastPermissionAttentionState = needsAttention
        statusItem.button?.image = NSImage.birdStatus(size: 20, needsAttention: needsAttention)
        statusItem.button?.toolTip = needsAttention ? "Говорун: нужны разрешения" : "Говорун"
        if needsAttention {
            DiagnosticsLog.record(
                "Нужны разрешения: \(missing.joined(separator: ", ")).",
                category: "Разрешения",
                level: .warning
            )
        } else {
            DiagnosticsLog.record("Разрешения включены.", category: "Разрешения")
        }
    }

    private func startPermissionStatusTimer() {
        permissionStatusTimer?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshStatusIcon()
            }
        }
        permissionStatusTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    // MARK: - Windows

    private func showStatsPopoverAuto() {
        guard settingsWindow?.isVisible != true else { return }
        autoCloseTask?.cancel()
        if statsPopover == nil {
            let vc = FirstMouseHostingController(
                rootView: StatsPopoverView(onOpenSettings: { [weak self] in
                    self?.statsPopover?.close()
                    self?.openSettings()
                })
            )
            let p = NSPopover()
            p.contentViewController = vc
            p.contentSize = NSSize(width: 236, height: 116)
            p.behavior = .transient
            statsPopover = p
        }
        guard let btn = statusItem.button else { return }
        statsPopover!.show(relativeTo: btn.bounds, of: btn, preferredEdge: .minY)
        autoCloseTask = Task {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            statsPopover?.close()
        }
    }


    private func showStatsPopover() {
        if statsPopover == nil {
            let vc = FirstMouseHostingController(
                rootView: StatsPopoverView(onOpenSettings: { [weak self] in
                    self?.statsPopover?.close()
                    self?.openSettings()
                })
            )
            let p = NSPopover()
            p.contentViewController = vc
            p.contentSize = NSSize(width: 236, height: 116)
            p.behavior = .transient
            statsPopover = p
        }
        guard let btn = statusItem.button else { return }
        NSApp.activate(ignoringOtherApps: true)
        statsPopover!.show(relativeTo: btn.bounds, of: btn, preferredEdge: .minY)
    }

    @objc func openSettings() {
        statsPopover?.close()
        if let w = settingsWindow, w.isVisible {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let view = SettingsView(onHotkeyChanged: { [weak self] in self?.restartHotkey() })
            .environmentObject(audioEngine)
        let hosting = NSHostingController(rootView: view)
        let win = NSWindow(contentViewController: hosting)
        win.title = "Говорун — Настройки"
        win.styleMask = [.titled, .closable, .miniaturizable]
        win.center()
        win.isReleasedWhenClosed = false
        settingsWindow = win
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Permissions

    @objc private func openAccessibilitySettings() {
        NSWorkspace.shared.open(
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        startPermissionCheckTimer()
    }

    @objc private func openMicSettings() {
        NSWorkspace.shared.open(
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
    }

    private func setupHotkeyIfTrusted() {
        guard AXIsProcessTrusted() else {
            DiagnosticsLog.record(
                "Ожидаю доступ к специальным возможностям для хоткея.",
                category: "Разрешения",
                level: .warning
            )
            startPermissionCheckTimer()
            return
        }
        setupHotkey()
    }

    // Poll until accessibility is available, then restart hotkey without prompting.
    private func startPermissionCheckTimer() {
        permissionCheckTimer?.invalidate()
        permissionCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] t in
            Task { @MainActor [weak self] in
                guard let self else { t.invalidate(); return }
                guard AXIsProcessTrusted() else { return }
                if !self.hotkeyManager.isActive {
                    self.hotkeyManager.stop()
                    self.hotkeyManager.reloadConfig()
                    self.setupHotkey()
                }
                if self.hotkeyManager.isActive {
                    DiagnosticsLog.record("Хоткей запущен после выдачи доступа.", category: "Хоткей")
                    t.invalidate()
                    self.permissionCheckTimer = nil
                }
            }
        }
    }

    // MARK: - Hotkey

    func restartHotkey() {
        hotkeyManager.stop()
        hotkeyManager.reloadConfig()
        setupHotkeyIfTrusted()
    }

    @objc private func restartHotkeyFromMenu() {
        restartHotkey()
    }

    private func setupHotkey() {
        hotkeyManager.onKeyDown = { [weak self] in
            Task { @MainActor in await self?.handleKeyDown() }
        }
        hotkeyManager.onKeyUp = { [weak self] in
            Task { @MainActor in await self?.handleKeyUp() }
        }
        hotkeyManager.onKeyAborted = { [weak self] in
            Task { @MainActor in await self?.abortRecording() }
        }
        hotkeyManager.onCancel = { [weak self] in
            Task { @MainActor in await self?.abortRecording() }
        }
        if !hotkeyManager.start() {
            DiagnosticsLog.record(
                "Хоткей не запущен. Проверь специальные возможности.",
                category: "Хоткей",
                level: .warning
            )
            startPermissionCheckTimer()
        } else {
            DiagnosticsLog.record("Хоткей запущен.", category: "Хоткей")
        }
    }

    private func handleKeyDown() async {
        switch recordingState {
        case .idle:
            guard !isStoppingRecording else { return }
            guard audioEngine.state == .idle else { return }
            recordingState = .recording(startedAt: Date())
            await startRecording()
        case .recording, .toggleMode:
            await finishRecording()
        }
    }

    private func handleKeyUp() async {
        guard case .recording(let startedAt) = recordingState else { return }
        let held = Date().timeIntervalSince(startedAt)
        if held >= pttThreshold {
            await finishRecording()
        } else {
            recordingState = .toggleMode(startedAt: startedAt)
        }
    }

    private func startRecording() async {
        hotkeyManager.isRecording = true
        updateRuntimeBusy()
        floatingWindowController?.show()
        RecordingSound.playStart()
        do {
            try await audioEngine.startRecording()
            DiagnosticsLog.record("Запись началась.", category: "Запись")
            audioMuter.muteIfNeeded()
            scheduleMaxDurationStop()
        } catch {
            DiagnosticsLog.record(
                "Не удалось начать запись: \(error.localizedDescription)",
                category: "Запись",
                level: .error
            )
            hotkeyManager.isRecording = false
            recordingState = .idle
            updateRuntimeBusy()
            audioMuter.unmuteIfNeeded()
            floatingWindowController?.hide()
        }
    }

    // Автоматически завершает запись, если она длится дольше лимита.
    private func scheduleMaxDurationStop() {
        maxDurationTask?.cancel()
        let minutes = RecordingOptions.maxRecordingMinutes
        guard minutes > 0 else { maxDurationTask = nil; return }
        maxDurationTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(minutes * 60))
            guard !Task.isCancelled else { return }
            await self?.finishRecording()
        }
    }

    private func finishRecording() async {
        guard !isStoppingRecording else { return }
        isStoppingRecording = true
        updateRuntimeBusy()

        maxDurationTask?.cancel(); maxDurationTask = nil
        hotkeyManager.isRecording = false
        let startedAt: Date? = {
            switch recordingState {
            case .recording(let t), .toggleMode(let t):
                return t
            case .idle:
                return nil
            }
        }()
        floatingWindowController?.hide()
        audioMuter.unmuteIfNeeded()
        RecordingSound.playStop()        // сразу слышно, что запись остановлена

        try? await Task.sleep(for: .milliseconds(120))
        let job = audioEngine.stopRecordingForRecognition()
        DiagnosticsLog.record(
            "Запись остановлена: \(job.chunkCount) фрагм., \(formatSeconds(job.speechSamples)) речи.",
            category: "Запись"
        )
        recordingState = .idle
        isStoppingRecording = false
        updateRuntimeBusy()
        enqueueRecognition(job, startedAt: startedAt)
    }

    private func enqueueRecognition(_ job: AudioEngine.RecognitionJob, startedAt: Date?) {
        guard !job.isEmpty else {
            updateRuntimeBusy()
            return
        }

        queuedRecognitionJobs += 1
        updateRuntimeBusy()

        let previous = recognitionTail
        recognitionTail = Task { [weak self] in
            await previous?.value
            await self?.processRecognition(job, startedAt: startedAt)
        }
    }

    private func processRecognition(_ job: AudioEngine.RecognitionJob, startedAt: Date?) async {
        defer {
            queuedRecognitionJobs = max(0, queuedRecognitionJobs - 1)
            updateRuntimeBusy()
        }

        let recognitionStartedAt = CFAbsoluteTimeGetCurrent()
        let recognizedText = await audioEngine.recognize(job)
        let recognitionMs = Int((CFAbsoluteTimeGetCurrent() - recognitionStartedAt) * 1000)
        DiagnosticsLog.record(
            "Распознавание завершено: \(formatMilliseconds(recognitionMs)), \(job.chunkCount) фрагм.",
            category: "Распознавание"
        )
        var text = WordDictionary.apply(to: recognizedText)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            DiagnosticsLog.record("Распознавание вернуло пустой текст.", category: "Распознавание", level: .warning)
            return
        }

        let seconds = startedAt.map { Int(Date().timeIntervalSince($0)) } ?? job.speechSamples / 16000
        let zoneBefore = WarningSettings.zone(minutes: SessionStats.secondsToday / 60)
        SessionStats.record(text: text, seconds: seconds)
        NotificationCenter.default.post(name: .statsDidUpdate, object: nil)
        let zoneAfter = WarningSettings.zone(minutes: SessionStats.secondsToday / 60)
        if zoneAfter != zoneBefore, zoneAfter != .green {
            showStatsPopoverAuto()
        }
        if LLMSettings.isEnabled {
            if text.count < LLMSettings.minLength {
                updateLLMStatus(nil)
            } else if let configurationError = LLMSettings.apiKeyConfigurationError() {
                updateLLMStatus(configurationError.localizedDescription)
                DiagnosticsLog.record(configurationError.localizedDescription, category: "LLM", level: .warning)
            } else {
                do {
                    let llmStartedAt = CFAbsoluteTimeGetCurrent()
                    let correctedText = try await LLMCorrector.shared.correct(text)
                    let llmMs = Int((CFAbsoluteTimeGetCurrent() - llmStartedAt) * 1000)
                    updateLLMStatus(nil)
                    if correctedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        DiagnosticsLog.record(
                            "LLM вернул пустой текст, вставляю распознанный вариант.",
                            category: "LLM",
                            level: .warning
                        )
                    } else {
                        text = correctedText
                        DiagnosticsLog.record("LLM-стилизация выполнена: \(formatMilliseconds(llmMs)).", category: "LLM")
                    }
                } catch {
                    updateLLMStatus(error.localizedDescription)
                    DiagnosticsLog.record(error.localizedDescription, category: "LLM", level: .error)
                }
            }
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        hotkeyManager.suppressSyntheticPasteEvents(seconds: PasteManager.syntheticEventSuppressionSeconds)
        await PasteManager.paste(text + " ")
        DiagnosticsLog.record("Текст скопирован в буфер и вставлен.", category: "Вставка")
    }

    private func updateLLMStatus(_ message: String?) {
        let normalized = message?.trimmingCharacters(in: .whitespacesAndNewlines)
        let next = normalized?.isEmpty == false ? normalized : nil
        guard LLMSettings.lastErrorMessage != next else { return }
        LLMSettings.lastErrorMessage = next
        NotificationCenter.default.post(name: .llmStatusDidUpdate, object: nil)
    }

    private func refreshLLMConfigurationStatus() {
        guard LLMSettings.isEnabled else {
            updateLLMStatus(nil)
            return
        }
        updateLLMStatus(LLMSettings.apiKeyConfigurationError()?.localizedDescription)
    }

    private func abortRecording() async {
        if case .idle = recordingState { return }
        maxDurationTask?.cancel(); maxDurationTask = nil
        hotkeyManager.isRecording = false
        recordingState = .idle
        audioEngine.cancelRecording()
        DiagnosticsLog.record("Запись отменена.", category: "Запись")
        audioMuter.unmuteIfNeeded()
        RecordingSound.playStop()
        floatingWindowController?.hide()
        updateRuntimeBusy()
    }

    private func updateRuntimeBusy() {
        let microphoneBusy: Bool
        switch recordingState {
        case .idle:
            microphoneBusy = isStoppingRecording
        case .recording, .toggleMode:
            microphoneBusy = true
        }
        RuntimeState.set(
            microphoneActive: microphoneBusy,
            busy: microphoneBusy || queuedRecognitionJobs > 0
        )
    }

    private func formatSeconds(_ sampleCount: Int) -> String {
        let seconds = Double(sampleCount) / 16_000
        return String(format: "%.1f с", seconds)
    }

    private func formatMilliseconds(_ milliseconds: Int) -> String {
        milliseconds >= 1000
            ? String(format: "%.1f с", Double(milliseconds) / 1000)
            : "\(milliseconds) мс"
    }
}
