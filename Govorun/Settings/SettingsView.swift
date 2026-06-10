import SwiftUI
import AppKit
import ApplicationServices
import AVFoundation
import ServiceManagement
import Security

private enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case llm
    case stats
    case dictionary
    case diagnostics
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "Основные"
        case .llm:     return "LLM"
        case .stats:   return "Статистика"
        case .dictionary: return "Словарь"
        case .diagnostics: return "Диагностика"
        case .about: return "О программе"
        }
    }

    var systemImage: String {
        switch self {
        case .general: return "gearshape"
        case .llm:     return "sparkles"
        case .stats:   return "chart.bar"
        case .dictionary: return "textformat.alt"
        case .diagnostics: return "list.bullet.rectangle"
        case .about: return "info.circle"
        }
    }
}

struct SettingsView: View {
    var onHotkeyChanged: () -> Void = {}

    @EnvironmentObject var engine: AudioEngine

    @State private var selectedTab: SettingsTab = .general

    // General
    @State private var accessibilityGranted = AXIsProcessTrusted()
    @State private var micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    @State private var pauseLength:   PauseLength  = PauseLength.stored
    @State private var hotkey:        HotkeyConfig = HotkeyConfig.stored
    @State private var cancelHotkey:  HotkeyConfig = HotkeyConfig.cancelStored ?? HotkeyConfig.defaultCancel
    @State private var muteAudio:     Bool         = RecordingOptions.muteAudioDuringRecording
    @State private var playSounds:    Bool         = RecordingOptions.playRecordingSounds
    @State private var maxRecMinutes: Int          = RecordingOptions.maxRecordingMinutes
    @State private var launchAtLogin: Bool         = SMAppService.mainApp.status == .enabled
    @State private var dictionaryEnabled: Bool     = WordDictionary.isEnabled
    @State private var dictionaryText: String      = WordDictionary.toText()
    @State private var dictionarySaved             = false

    // Warnings (зоны по минутам речи за день)
    @State private var warningsEnabled: Bool = WarningSettings.isEnabled
    @State private var warningYellow:   Int  = WarningSettings.yellowMinutes
    @State private var warningRed:      Int  = WarningSettings.redMinutes

    // LLM
    @State private var llmEnabled:      Bool        = LLMSettings.isEnabled
    @State private var llmProvider:     LLMProvider = LLMSettings.provider
    @State private var llmURL:          String      = LLMSettings.serverURL
    @State private var llmKey:          String      = ""
    @State private var llmKeyState:     LLMApiKeyStorageState = LLMSettings.apiKeyStorageState
    @State private var llmModel:        String      = LLMSettings.model
    @State private var llmModels:       [String]    = []
    @State private var llmLoading:      Bool        = false
    @State private var llmChecking:     Bool        = false
    @State private var llmError:        String?     = nil
    @State private var llmMinLength:    Int         = LLMSettings.minLength
    @State private var llmProxyEnabled: Bool        = LLMSettings.proxyEnabled
    @State private var llmProxyURL:     String      = LLMSettings.proxyURL
    @State private var llmPrompt:       String      = LLMSettings.systemPrompt
    @State private var llmRuntimeError: String?     = LLMSettings.lastErrorMessage
    @State private var llmKeySaveMessage: String?   = nil
    @State private var llmKeySaveFailed: Bool       = false
    @State private var diagnosticsEvents: [DiagnosticEvent] = DiagnosticsLog.all()

    // About
    @State private var showLicenses = false

    var body: some View {
        HStack(spacing: 0) {
            SettingsSidebar(selection: $selectedTab, generalNeedsAttention: missingRequiredPermissions)

            Divider()

            Group {
                switch selectedTab {
                case .general:
                    generalTab
                case .llm:
                    llmTab
                case .stats:
                    StatsView()
                case .dictionary:
                    dictionaryTab
                case .diagnostics:
                    diagnosticsTab
                case .about:
                    aboutTab
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(width: 720, height: 580)
        .background(GovorunTheme.pageBackground)
        .onAppear {
            refreshPermissionState()
            dictionaryText = WordDictionary.toText()
            diagnosticsEvents = DiagnosticsLog.all()
        }
        .onReceive(Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()) { _ in
            refreshPermissionState()
        }
        .onReceive(NotificationCenter.default.publisher(for: .llmStatusDidUpdate)) { _ in
            refreshLLMKeyState()
            llmRuntimeError = LLMSettings.lastErrorMessage
        }
        .onReceive(NotificationCenter.default.publisher(for: DiagnosticsLog.didUpdate).receive(on: RunLoop.main)) { _ in
            diagnosticsEvents = DiagnosticsLog.all()
        }
        .sheet(isPresented: $showLicenses) { LicensesView() }
    }

    private var micGranted: Bool { micStatus == .authorized }

    private var missingRequiredPermissions: Bool {
        !accessibilityGranted || !micGranted
    }

    private func refreshPermissionState() {
        accessibilityGranted = AXIsProcessTrusted()
        micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    }

    // MARK: - Таб «Основные»

    private var generalTab: some View {
        SettingsPage {
            SettingsSection("Горячие клавиши") {
                SettingsRow("Запуск / остановка") {
                    HotkeyRecorderView(config: $hotkey) {
                        HotkeyConfig.stored = hotkey
                        onHotkeyChanged()
                    }
                }
                SettingsRow("Отмена записи") {
                    HotkeyRecorderView(config: $cancelHotkey) {
                        HotkeyConfig.cancelStored = cancelHotkey
                        onHotkeyChanged()
                    }
                }
                Text("Удержание — PTT. Короткое нажатие — переключение.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Рекомендуется Right ⌥. Правый ⌘ можно оставить; ⌘V нельзя назначить отдельным хоткеем.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            SettingsSection("Распознавание") {
                SettingsRow("Пауза между фразами", subtitle: "После паузы фраза считается завершённой") {
                    Stepper(pauseLabel, onIncrement: incrementPause, onDecrement: decrementPause)
                        .frame(width: 104, alignment: .trailing)
                }
                SettingsRow("Макс. длительность записи", subtitle: "Запись сама остановится и распознается по достижении лимита") {
                    Stepper(maxRecLabel, value: $maxRecMinutes, in: 0...180, step: 5)
                        .frame(width: 142, alignment: .trailing)
                        .onChange(of: maxRecMinutes) { RecordingOptions.maxRecordingMinutes = max(0, $0) }
                }
            }

            SettingsSection("Напоминание об отдыхе") {
                Toggle(isOn: $warningsEnabled) {
                    RowLabel(
                        title: "Следить за временем речи",
                        subtitle: "Птичка напомнит отдохнуть, если диктовки за день затянулись"
                    )
                }
                .onChange(of: warningsEnabled) { WarningSettings.isEnabled = $0 }

                if warningsEnabled {
                    SettingsRow("Первое напоминание", subtitle: "Когда суммарная речь за день дошла до порога") {
                        Stepper("\(warningYellow) мин", value: $warningYellow, in: yellowRange, step: 5)
                            .frame(width: 116, alignment: .trailing)
                            .onChange(of: warningYellow) {
                                warningYellow = min($0, warningRed - 5)
                                WarningSettings.yellowMinutes = warningYellow
                                NotificationCenter.default.post(name: .statsDidUpdate, object: nil)
                            }
                    }
                    SettingsRow("Настойчивое напоминание", subtitle: "Когда лучше остановиться и сделать перерыв") {
                        Stepper("\(warningRed) мин", value: $warningRed, in: redRange, step: 5)
                            .frame(width: 116, alignment: .trailing)
                            .onChange(of: warningRed) {
                                warningRed = max($0, warningYellow + 5)
                                WarningSettings.redMinutes = warningRed
                                NotificationCenter.default.post(name: .statsDidUpdate, object: nil)
                            }
                    }
                }
            }

            SettingsSection("Система") {
                Toggle("Звук начала и конца записи", isOn: $playSounds)
                    .onChange(of: playSounds) { RecordingOptions.playRecordingSounds = $0 }
                Toggle("Приглушить звук при записи", isOn: $muteAudio)
                    .onChange(of: muteAudio) { RecordingOptions.muteAudioDuringRecording = $0 }
                Toggle("Запускать при входе в систему", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { v in
                        do {
                            if v { try SMAppService.mainApp.register() }
                            else { try SMAppService.mainApp.unregister() }
                        } catch {
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
            }

            SettingsSection("Разрешения") {
                PermissionRow(
                    granted: accessibilityGranted,
                    label: "Специальные возможности",
                    okText: "Включено",
                    problemText: "Нужно включить",
                    buttonTitle: "Открыть",
                    action: {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                        refreshPermissionState()
                    }
                )
                PermissionRow(
                    granted: micGranted,
                    label: "Микрофон",
                    okText: "Включено",
                    problemText: micProblemText,
                    buttonTitle: micButtonTitle,
                    action: requestOrOpenMicrophonePermission
                )

                if missingRequiredPermissions {
                    Text("После включения специальных возможностей macOS иногда применяет доступ через несколько секунд. Если статус не обновился, перезапусти Говорун.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var micProblemText: String {
        switch micStatus {
        case .notDetermined: return "Нужно разрешить"
        case .denied, .restricted: return "Нужно включить"
        case .authorized: return "Включено"
        @unknown default: return "Нужно проверить"
        }
    }

    private var micButtonTitle: String {
        micStatus == .notDetermined ? "Разрешить" : "Открыть"
    }

    private func requestOrOpenMicrophonePermission() {
        if micStatus == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { _ in
                DispatchQueue.main.async {
                    refreshPermissionState()
                }
            }
        } else {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
            refreshPermissionState()
        }
    }

    // MARK: - Таб «LLM»

    private var llmTab: some View {
        SettingsPage {
            SettingsSection {
                Toggle(isOn: $llmEnabled) {
                    RowLabel(
                        title: "Улучшать текст после распознавания",
                        subtitle: "Убирает паразиты, расставляет знаки препинания, исправляет термины"
                    )
                }
                .onChange(of: llmEnabled) {
                    LLMSettings.isEnabled = $0
                    refreshLLMKeyState()
                    if !$0 { clearLLMRuntimeError() }
                }

                if let notice = llmNotice {
                    SettingsNotice(text: notice, tint: GovorunTheme.amber)
                }
            }

            if llmEnabled {
                SettingsSection("Подключение") {
                    SettingsRow("Провайдер") {
                        Picker("", selection: $llmProvider) {
                            ForEach(LLMProvider.allCases, id: \.self) { Text($0.label).tag($0) }
                        }
                        .labelsHidden()
                        .frame(width: 176)
                        .onChange(of: llmProvider) { v in
                            LLMSettings.provider = v
                            llmURL = LLMSettings.serverURL
                            llmKey = ""
                            refreshLLMKeyState()
                            clearLLMRuntimeError()
                            llmModel = LLMSettings.model
                            llmModels = []
                            llmError = nil
                        }
                    }

                    SettingsRow("Сервер") {
                        HStack(spacing: 6) {
                            TextField("", text: $llmURL)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 220)
                                .onChange(of: llmURL) { v in
                                    LLMSettings.serverURL = v
                                    llmModels = []
                                    llmError = nil
                                    clearLLMRuntimeError()
                                    refreshLLMKeyState()
                                }
                            if llmURL != llmProvider.defaultURL {
                                Button {
                                    llmURL = llmProvider.defaultURL
                                    LLMSettings.serverURL = llmURL
                                    clearLLMRuntimeError()
                                    refreshLLMKeyState()
                                } label: {
                                    Image(systemName: "arrow.counterclockwise")
                                        .font(.system(size: 11))
                                }
                                .buttonStyle(.borderless)
                                .foregroundStyle(.secondary)
                                .help("Сбросить к значению по умолчанию")
                            }
                        }
                    }

                    if llmApiKeyRowVisible {
                        VStack(alignment: .leading, spacing: 8) {
                            RowLabel(
                                title: "API ключ",
                                subtitle: "Сохраняется в Keychain macOS"
                            )

                            SecureField(llmKeyPlaceholder, text: $llmKey)
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: .infinity)
                                .onSubmit(saveLLMKey)
                                .onChange(of: llmKey) { value in
                                    if !value.isEmpty {
                                        llmKeySaveMessage = nil
                                        llmKeySaveFailed = false
                                    }
                                }

                            HStack(spacing: 8) {
                                Button {
                                    saveLLMKey()
                                } label: {
                                    Label("Сохранить ключ", systemImage: "checkmark")
                                }
                                .controlSize(.small)
                                .buttonStyle(.borderedProminent)
                                .disabled(llmChecking || llmKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                                Button {
                                    checkLLMConnection()
                                } label: {
                                    Label(llmChecking ? "Проверяю" : "Проверить", systemImage: llmChecking ? "ellipsis" : "network")
                                }
                                .controlSize(.small)
                                .disabled(llmChecking || llmLoading)

                                Button {
                                    resetLLMKeyStorage()
                                } label: {
                                    Label(llmKeyState.isVisibleInSettings ? "Удалить" : "Сбросить", systemImage: "trash")
                                }
                                .controlSize(.small)
                                .foregroundStyle(.red)
                                .help("Удалить ключ и сбросить состояние хранилища")

                                Spacer(minLength: 0)
                            }

                            if let hint = llmKeyHint {
                                Text(hint)
                                    .font(.system(size: 10))
                                    .foregroundStyle(llmKeyHintColor)
                                    .lineLimit(3)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    SettingsRow("Модель") {
                        HStack(spacing: 6) {
                            if llmModels.isEmpty {
                                Text(llmModel.isEmpty ? "–" : llmModel)
                                    .foregroundStyle(llmModel.isEmpty ? .secondary : .primary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .frame(width: 174, alignment: .trailing)
                            } else {
                                Picker("", selection: $llmModel) {
                                    ForEach(llmModels, id: \.self) { Text($0).tag($0) }
                                }
                                .labelsHidden()
                                .frame(width: 174)
                                .onChange(of: llmModel) { v in
                                    guard !v.isEmpty else { return }
                                    LLMSettings.model = v
                                }
                            }
                            Button { loadModels() } label: {
                                Image(systemName: llmLoading ? "ellipsis" : "arrow.clockwise")
                                    .font(.system(size: 12))
                            }
                            .buttonStyle(.borderless)
                            .disabled(llmLoading || llmURL.isEmpty)
                        }
                    }

                    if let err = llmError {
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                SettingsSection("Параметры") {
                    SettingsRow("Минимальная длина", subtitle: "Текст короче не отправляется на обработку") {
                        Stepper("\(llmMinLength) симв.", value: $llmMinLength, in: 10...500, step: 10)
                            .frame(width: 128, alignment: .trailing)
                            .onChange(of: llmMinLength) { LLMSettings.minLength = max(10, $0) }
                    }

                    Toggle("Использовать прокси", isOn: $llmProxyEnabled)
                        .onChange(of: llmProxyEnabled) { LLMSettings.proxyEnabled = $0 }
                    if llmProxyEnabled {
                        SettingsRow("Прокси") {
                            TextField("", text: $llmProxyURL)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 220)
                                .onChange(of: llmProxyURL) { LLMSettings.proxyURL = $0 }
                        }
                    }
                }

                SettingsSection("Системный промпт") {
                    TextEditor(text: $llmPrompt)
                        .font(.system(.caption, design: .monospaced))
                        .frame(height: 90)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .govorunFieldSurface(cornerRadius: 6)
                        .onChange(of: llmPrompt) { LLMSettings.systemPrompt = $0 }
                    HStack {
                        Button("Сбросить") {
                            llmPrompt = LLMCorrector.defaultPrompt
                            LLMSettings.systemPrompt = llmPrompt
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.red)
                        .font(.caption)
                        Spacer()
                        Text("\(llmPrompt.count) симв.")
                            .font(.caption)
                            .foregroundStyle(.quaternary)
                    }
                }
            }
        }
    }

    // MARK: - Таб «Словарь»

    private var dictionaryTab: some View {
        SettingsPage {
            SettingsSection {
                Toggle(isOn: $dictionaryEnabled) {
                    RowLabel(
                        title: "Использовать словарь замен",
                        subtitle: "Правила применяются после распознавания и до LLM-обработки"
                    )
                }
                .onChange(of: dictionaryEnabled) { WordDictionary.isEnabled = $0 }
            }

            SettingsSection("Правила замен") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        RowLabel(
                            title: "Локальный словарь",
                            subtitle: "Применяется сразу после распознавания и до LLM-обработки"
                        )
                        Spacer(minLength: 12)
                        if dictionarySaved {
                            Text("Сохранено")
                                .font(.caption)
                                .foregroundStyle(Color(nsColor: GovorunTheme.green))
                        }
                        Button {
                            dictionaryText = WordDictionary.toText()
                            dictionarySaved = false
                        } label: {
                            Label("Сбросить", systemImage: "arrow.counterclockwise")
                        }
                        .controlSize(.small)

                        Button {
                            WordDictionary.fromText(dictionaryText)
                            dictionaryText = WordDictionary.toText()
                            dictionarySaved = true
                        } label: {
                            Label("Сохранить", systemImage: "checkmark")
                        }
                        .controlSize(.small)
                        .buttonStyle(.borderedProminent)
                    }

                    TextEditor(text: $dictionaryText)
                        .font(.system(size: 12, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .padding(10)
                        .frame(minHeight: 300)
                        .govorunFieldSurface()
                        .onChange(of: dictionaryText) { _ in dictionarySaved = false }
                }
            }

            SettingsSection("Формат") {
                ForEach(Self.dictionaryExamples, id: \.example) { row in
                    DictionaryExampleRow(example: row.example, detail: row.detail)
                }
            }
        }
    }

    // MARK: - Таб «Диагностика»

    private var diagnosticsTab: some View {
        SettingsPage {
            SettingsSection {
                HStack(alignment: .center, spacing: 12) {
                    RowLabel(
                        title: "События приложения",
                        subtitle: "Последние \(DiagnosticsLog.maxStoredEvents) событий: права, LLM, прокси, распознавание и запуск. Текст диктовки и API-ключи не сохраняются."
                    )

                    Spacer(minLength: 12)

                    Button {
                        copyDiagnostics()
                    } label: {
                        Label("Скопировать", systemImage: "doc.on.doc")
                    }
                    .controlSize(.small)

                    Button {
                        DiagnosticsLog.clear()
                        diagnosticsEvents = []
                    } label: {
                        Label("Очистить", systemImage: "trash")
                    }
                    .controlSize(.small)
                    .foregroundStyle(.red)
                    .disabled(diagnosticsEvents.isEmpty)
                }
            }

            SettingsSection("Последние события") {
                if diagnosticsEvents.isEmpty {
                    Text("Пока нет событий.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(diagnosticsEvents.reversed())) { event in
                            DiagnosticEventRow(event: event)
                            if event.id != diagnosticsEvents.first?.id {
                                Divider()
                                    .padding(.leading, 34)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Таб «О программе»

    private var aboutTab: some View {
        SettingsPage {
            SettingsSection {
                HStack(alignment: .center, spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Говорун")
                            .font(.system(size: 18, weight: .semibold))
                        Text("Версия \(version)")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Text("Офлайн-диктовка на русском для menu bar")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)
                }
            }

            SettingsSection("Приватность") {
                AboutFactRow(
                    icon: "waveform",
                    title: "Распознавание речи",
                    detail: "Звук обрабатывается локально и не покидает устройство",
                    value: "Офлайн"
                )
                AboutFactRow(
                    icon: "sparkles",
                    title: "LLM-стилизация",
                    detail: "Текст отправляется только на сервер, указанный в настройках",
                    value: "Опционально"
                )
                AboutFactRow(
                    icon: "key",
                    title: "API-ключи",
                    detail: "Сохраняются в системной цепочке ключей macOS",
                    value: "Keychain"
                )
            }

            SettingsSection("Проект") {
                AboutLinkRow(title: "Автор", value: "Дмитрий Киселев", urlTitle: "@amidexe", url: "https://github.com/amidexe")
                AboutLinkRow(title: "Исходный код", value: "GitHub", urlTitle: "govorun-osx", url: "https://github.com/amidexe/govorun-osx")
            }

            SettingsSection("Компоненты") {
                SettingsRow("GigaAM v3 · Silero VAD · sherpa-onnx", subtitle: "Модели и рантайм локального распознавания") {
                    Button {
                        showLicenses = true
                    } label: {
                        Label("Лицензии", systemImage: "scroll")
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private static let dictionaryExamples: [(example: String, detail: String)] = [
        ("ё = е", "символ заменяется везде"),
        ("дев = dev", "слово заменяется только целиком"),
        ("опен эй ай = OpenAI", "фраза заменяется в любом месте"),
        ("кхм =", "пустая замена удаляет фрагмент"),
        ("# комментарий", "строки с решёткой игнорируются")
    ]

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-"
    }

    private var pauseLabel: String {
        switch pauseLength {
        case .short:  return "0.5 с"
        case .medium: return "1 с"
        case .long:   return "2 с"
        }
    }

    private var maxRecLabel: String {
        maxRecMinutes == 0 ? "∞ без лимита" : "\(maxRecMinutes) мин"
    }

    private var yellowRange: ClosedRange<Int> {
        5...max(5, warningRed - 5)
    }

    private var redRange: ClosedRange<Int> {
        min(max(warningYellow + 5, 10), 600)...600
    }

    private func incrementPause() {
        guard pauseLength != .long else { return }
        pauseLength = pauseLength == .short ? .medium : .long
        PauseLength.stored = pauseLength
    }

    private func decrementPause() {
        guard pauseLength != .short else { return }
        pauseLength = pauseLength == .long ? .medium : .short
        PauseLength.stored = pauseLength
    }

    private func loadModels() {
        llmLoading = true
        llmError = nil
        let snap = llmProvider
        Task {
            do {
                let models = try await LLMCorrector.shared.fetchModels()
                guard llmProvider == snap else {
                    llmLoading = false
                    return
                }
                llmModels = models
                if llmModel.isEmpty || !models.contains(llmModel) {
                    llmModel = models.first ?? ""
                }
                LLMSettings.model = llmModel
                clearLLMRuntimeError()
                DiagnosticsLog.record("Список моделей загружен.", category: "LLM")
            } catch {
                let message = error.localizedDescription
                llmError = message
                LLMSettings.lastErrorMessage = message
                llmRuntimeError = message
                DiagnosticsLog.record(message, category: "LLM", level: .error)
                NotificationCenter.default.post(name: .llmStatusDidUpdate, object: nil)
            }
            llmLoading = false
        }
    }

    private func refreshLLMKeyState() {
        llmKeyState = LLMSettings.apiKeyStorageState
        if llmKeyState == .saved, llmRuntimeError?.localizedCaseInsensitiveContains("ключ \(llmProvider.label)") == true {
            clearLLMRuntimeError()
        }
    }

    private func clearLLMRuntimeError() {
        LLMSettings.lastErrorMessage = nil
        llmRuntimeError = nil
        NotificationCenter.default.post(name: .llmStatusDidUpdate, object: nil)
    }

    private func saveLLMKey() {
        let value = llmKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }

        let status = LLMSettings.saveApiKey(value)
        refreshLLMKeyState()

        if status == errSecSuccess {
            llmKey = ""
            llmKeyState = .saved
            llmKeySaveMessage = "Ключ сохранён. Проверяю подключение…"
            llmKeySaveFailed = false
            llmError = nil
            clearLLMRuntimeError()
            DiagnosticsLog.record("Ключ \(llmProvider.label) сохранён.", category: "LLM")
            checkLLMConnection()
        } else {
            let message = "Не удалось сохранить ключ \(llmProvider.label): \(KeychainHelper.message(for: status))."
            llmKeySaveMessage = message
            llmKeySaveFailed = true
            llmRuntimeError = message
            LLMSettings.lastErrorMessage = message
            DiagnosticsLog.record(message, category: "LLM", level: .error)
            NotificationCenter.default.post(name: .llmStatusDidUpdate, object: nil)
        }
    }

    private var llmApiKeyRowVisible: Bool {
        LLMSettings.requiresApiKey || llmKeyState.isVisibleInSettings
    }

    private func resetLLMKeyStorage() {
        llmKey = ""
        _ = LLMSettings.saveApiKey("")
        refreshLLMKeyState()
        clearLLMRuntimeError()
        llmKeySaveMessage = "Хранилище ключа сброшено."
        llmKeySaveFailed = false
        DiagnosticsLog.record("Хранилище ключа \(llmProvider.label) сброшено.", category: "LLM")
    }

    private func checkLLMConnection() {
        llmChecking = true
        llmError = nil
        refreshLLMKeyState()

        Task {
            do {
                let message = try await LLMCorrector.shared.checkConnection()
                refreshLLMKeyState()
                llmKeySaveMessage = message
                llmKeySaveFailed = false
                llmError = nil
                clearLLMRuntimeError()
                DiagnosticsLog.record(message, category: "LLM")
            } catch {
                refreshLLMKeyState()
                let message = error.localizedDescription
                llmKeySaveMessage = message
                llmKeySaveFailed = true
                llmError = message
                llmRuntimeError = message
                LLMSettings.lastErrorMessage = message
                DiagnosticsLog.record(message, category: "LLM", level: .error)
                NotificationCenter.default.post(name: .llmStatusDidUpdate, object: nil)
            }
            llmChecking = false
        }
    }

    private func copyDiagnostics() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(DiagnosticsLog.textDump(), forType: .string)
    }

    private var llmKeyPlaceholder: String {
        switch llmKeyState {
        case .missing:
            return llmProvider.keyPlaceholder
        case .saved:
            return "сохранён; введи новый для замены"
        case .inaccessible:
            return "недоступен; введи заново"
        case .staleReference:
            return "не найден; введи заново"
        }
    }

    private var llmKeyHint: String? {
        if let llmKeySaveMessage {
            return llmKeySaveMessage
        }
        switch llmKeyState {
        case .missing:
            return nil
        case .saved:
            return "Ключ сохранён."
        case .inaccessible:
            return "macOS не даёт доступ. Введи ключ заново."
        case .staleReference:
            return "Ключ не найден в Keychain."
        }
    }

    private var llmKeyHintColor: Color {
        if llmKeySaveMessage != nil {
            return llmKeySaveFailed ? .orange : Color(nsColor: GovorunTheme.green)
        }
        switch llmKeyState {
        case .saved:
            return .secondary
        case .missing:
            return .secondary
        case .inaccessible, .staleReference:
            return .orange
        }
    }

    private var llmNotice: String? {
        if llmEnabled, let error = LLMSettings.apiKeyConfigurationError() {
            return error.localizedDescription
        }
        return llmRuntimeError?.isEmpty == false ? llmRuntimeError : nil
    }

    private var llmKeyAccessProblemText: String {
        switch llmKeyState {
        case .missing:
            return "Ключ \(llmProvider.label) не задан."
        case .inaccessible:
            return "macOS не даёт доступ к ключу \(llmProvider.label)."
        case .staleReference:
            return "Ключ \(llmProvider.label) не найден в Keychain."
        case .saved:
            return "Ключ \(llmProvider.label) не удалось прочитать. Введи его заново."
        }
    }
}

// MARK: - Stable settings layout

private struct SettingsSidebar: View {
    @Binding var selection: SettingsTab
    let generalNeedsAttention: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Говорун")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.bottom, 8)

            ForEach(SettingsTab.allCases) { tab in
                Button {
                    selection = tab
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: tab.systemImage)
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 18)
                        Text(tab.title)
                            .font(.system(size: 13, weight: selection == tab ? .semibold : .regular))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        if tab == .general && generalNeedsAttention {
                            Image(systemName: "exclamationmark.circle.fill")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.orange)
                                .help("Нужно включить разрешения")
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 7)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(selection == tab ? Color.accentColor : Color.primary.opacity(0.86))
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(selection == tab ? Color.accentColor.opacity(0.14) : Color.clear)
                )
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(width: 158)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(GovorunTheme.sidebarBackground)
    }
}

private struct SettingsPage<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                content
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(GovorunTheme.pageBackground)
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String?
    let content: Content

    init(_ title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .padding(.horizontal, 2)
            }

            VStack(alignment: .leading, spacing: 10) {
                content
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .govorunSurface()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SettingsNotice: View {
    let text: String
    let tint: NSColor

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(nsColor: tint))
                .padding(.top, 1)
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(8)
        .background(
            Color(nsColor: tint).opacity(0.10),
            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
        )
    }
}

private struct SettingsRow<Content: View>: View {
    let title: String
    let subtitle: String?
    let content: Content

    init(_ title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            RowLabel(title: title, subtitle: subtitle)
                .frame(maxWidth: .infinity, alignment: .leading)
            content
        }
        .frame(minHeight: 28)
    }
}

private struct RowLabel: View {
    let title: String
    let subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct DictionaryExampleRow: View {
    let example: String
    let detail: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(example)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: 190, alignment: .leading)

            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct DiagnosticEventRow: View {
    let event: DiagnosticEvent

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: iconName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 24, height: 24)
                .background(
                    tint.opacity(0.11),
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(event.category)
                        .font(.system(size: 12, weight: .semibold))
                    Text(event.date.formatted(date: .omitted, time: .standard))
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }

                Text(event.message)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 7)
    }

    private var iconName: String {
        switch event.level {
        case .info: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.circle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }

    private var tint: Color {
        switch event.level {
        case .info: return Color(nsColor: GovorunTheme.green)
        case .warning: return Color(nsColor: GovorunTheme.amber)
        case .error: return Color(nsColor: GovorunTheme.red)
        }
    }
}

private struct AboutFactRow: View {
    let icon: String
    let title: String
    let detail: String
    let value: String

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(nsColor: GovorunTheme.blue))
                .frame(width: 24, height: 24)
                .background(
                    Color(nsColor: GovorunTheme.blue).opacity(0.11),
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Text(value)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }
}

private struct AboutLinkRow: View {
    let title: String
    let value: String
    let urlTitle: String
    let url: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
            Text(value)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Link(urlTitle, destination: URL(string: url)!)
                .font(.system(size: 11, weight: .medium))
        }
    }
}

// MARK: - Permission row

private struct PermissionRow: View {
    let granted: Bool
    let label: String
    let okText: String
    let problemText: String
    let buttonTitle: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(granted ? .green : .orange)

            Text(label)
                .font(.system(size: 12, weight: .semibold))

            Text(granted ? okText : problemText)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Spacer(minLength: 8)

            if !granted {
                Button(buttonTitle, action: action)
                    .buttonStyle(.borderless)
            }
        }
    }
}
