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

    private enum RecordingState {
        case idle
        case recording(startedAt: Date)
        case toggleMode
    }
    private var recordingState: RecordingState = .idle
    private let pttThreshold: TimeInterval = 0.35
    // Single-flight: пока идёт завершение записи + вставка, повторный вход запрещён.
    // Защищает от любой петли/наложения, которая могла бы спамить вставку.
    private var isFinishing = false
    // Автостоп по лимиту длительности записи (RecordingOptions.maxRecordingMinutes).
    private var maxDurationTask: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        // Сторож главного потока: если UI зависнет (напр. layout-loop SwiftUI),
        // приложение самозавершится, а не будет жечь CPU/батарею часами.
        MainThreadWatchdog.shared.start()
        LLMSettings.migrateKeysToKeychain()
        setupMenuBar()
        floatingWindowController = FloatingWindowController()
        requestPermissionsAndSetupHotkey()
        openSettingsForSmokeTestIfNeeded()
    }

    private func openSettingsForSmokeTestIfNeeded() {
        #if DEBUG
        guard ProcessInfo.processInfo.environment["GOVORUN_OPEN_SETTINGS_ON_LAUNCH"] == "1" else { return }
        DispatchQueue.main.async { [weak self] in
            self?.openSettings()
        }
        #endif
    }

    // MARK: - Menu bar

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let btn = statusItem.button!
        btn.image = NSImage.birdTemplate(size: 20)
        btn.target = self
        btn.action = #selector(handleStatusBarClick)
        btn.sendAction(on: [.leftMouseUp, .rightMouseUp])
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
        let axOk  = AXIsProcessTrusted()
        let micOk = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        let menu  = NSMenu()

        if !axOk {
            let item = NSMenuItem(title: "⚠️ Выдать права Accessibility…", action: #selector(openAccessibilitySettings), keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        if !micOk {
            let item = NSMenuItem(title: "⚠️ Выдать права Микрофон…", action: #selector(openMicSettings), keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        if !axOk || !micOk { menu.addItem(.separator()) }

        let settingsItem = NSMenuItem(title: "Настройки…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let resetItem = NSMenuItem(title: "Сбросить статистику за сегодня…", action: #selector(confirmResetToday), keyEquivalent: "")
        resetItem.target = self
        menu.addItem(resetItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Завершить Говорун", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
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
            p.contentSize = NSSize(width: 220, height: 100)
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
            p.contentSize = NSSize(width: 220, height: 100)
            p.behavior = .transient
            statsPopover = p
        }
        guard let btn = statusItem.button else { return }
        NSApp.activate(ignoringOtherApps: true)
        statsPopover!.show(relativeTo: btn.bounds, of: btn, preferredEdge: .minY)
    }

    @objc private func confirmResetToday() {
        let alert = NSAlert()
        alert.messageText = "Сбросить статистику за сегодня?"
        alert.informativeText = "Данные за сегодня будут удалены. Общая статистика останется."
        alert.addButton(withTitle: "Сбросить")
        alert.addButton(withTitle: "Отмена")
        alert.buttons[0].hasDestructiveAction = true
        if alert.runModal() == .alertFirstButtonReturn {
            SessionStats.resetToday()
            NotificationCenter.default.post(name: .statsDidUpdate, object: nil)
        }
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

    private func requestPermissionsAndSetupHotkey() {
        // Request mic
        AVCaptureDevice.requestAccess(for: .audio) { _ in }

        // Try to start hotkey; if no accessibility, prompt
        setupHotkey()

        if !AXIsProcessTrusted() {
            let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            AXIsProcessTrustedWithOptions(opts)
            startPermissionCheckTimer()
        }
    }

    // Poll until accessibility granted, then restart hotkey
    private func startPermissionCheckTimer() {
        permissionCheckTimer?.invalidate()
        permissionCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] t in
            Task { @MainActor [weak self] in
                guard let self else { t.invalidate(); return }
                if AXIsProcessTrusted() {
                    t.invalidate()
                    self.permissionCheckTimer = nil
                    self.hotkeyManager.stop()
                    self.setupHotkey()
                }
            }
        }
    }

    // MARK: - Hotkey

    func restartHotkey() {
        hotkeyManager.stop()
        hotkeyManager.reloadConfig()
        setupHotkey()
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
        hotkeyManager.start()
    }

    private func handleKeyDown() async {
        switch recordingState {
        case .idle:
            // Don't start if previous session is still transcribing
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
            recordingState = .toggleMode
        }
    }

    private func startRecording() async {
        hotkeyManager.isRecording = true
        floatingWindowController?.show()
        RecordingSound.playStart()       // mute внутри muter отложен, чтобы стартовый звук не обрезался
        audioMuter.muteIfNeeded()
        do {
            try await audioEngine.startRecording()
            scheduleMaxDurationStop()
        } catch {
            hotkeyManager.isRecording = false
            recordingState = .idle
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
        // Single-flight: не даём завершению/вставке наложиться или зациклиться.
        guard !isFinishing else { return }
        isFinishing = true
        defer { isFinishing = false }

        maxDurationTask?.cancel(); maxDurationTask = nil
        hotkeyManager.isRecording = false
        let startedAt: Date? = { if case .recording(let t) = recordingState { return t }; return nil }()
        recordingState = .idle
        floatingWindowController?.hide()
        audioMuter.unmuteIfNeeded()
        RecordingSound.playStop()        // сразу слышно, что запись остановлена
        try? await Task.sleep(for: .milliseconds(400))
        do {
            var text = try await audioEngine.stopRecording()
            text = WordDictionary.apply(to: text)
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let seconds = startedAt.map { Int(Date().timeIntervalSince($0)) } ?? audioEngine.speechSamples / 16000
                let zoneBefore = WarningSettings.zone(minutes: SessionStats.secondsToday / 60)
                SessionStats.record(text: text, seconds: seconds)
                NotificationCenter.default.post(name: .statsDidUpdate, object: nil)
                let zoneAfter = WarningSettings.zone(minutes: SessionStats.secondsToday / 60)
                if zoneAfter != zoneBefore, zoneAfter != .green {
                    showStatsPopoverAuto()
                }
                if LLMSettings.isEnabled {
                    do {
                        text = try await LLMCorrector.shared.correct(text)
                    } catch {
                    }
                }
                // Перепроверяем уже ПОСЛЕ LLM: если коррекция вернула пусто/пробелы,
                // ничего не вставляем — иначе в буфер уедет один голый пробел.
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                // Suspend tap so our own synthetic ⌘V doesn't re-trigger the hotkey
                hotkeyManager.suspendForRecorder()
                PasteManager.paste(text + " ")
                try? await Task.sleep(for: .milliseconds(150))
                hotkeyManager.resumeAfterRecorder()
            }
        } catch {
            // silent
        }
    }

    private func abortRecording() async {
        if case .idle = recordingState { return }
        maxDurationTask?.cancel(); maxDurationTask = nil
        hotkeyManager.isRecording = false
        recordingState = .idle
        _ = try? await audioEngine.stopRecording()
        audioMuter.unmuteIfNeeded()
        RecordingSound.playStop()
        floatingWindowController?.hide()
    }
}
