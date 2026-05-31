import SwiftUI
import ApplicationServices
import AVFoundation
import ServiceManagement

struct SettingsView: View {
    var onHotkeyChanged: () -> Void = {}

    @EnvironmentObject var engine: AudioEngine

    // General
    @State private var accessibilityGranted = AXIsProcessTrusted()
    @State private var micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    @State private var pauseLength:   PauseLength  = PauseLength.stored
    @State private var hotkey:        HotkeyConfig = HotkeyConfig.stored
    @State private var cancelHotkey:  HotkeyConfig = HotkeyConfig.cancelStored ?? HotkeyConfig.defaultCancel
    @State private var muteAudio:     Bool         = RecordingOptions.muteAudioDuringRecording
    @State private var launchAtLogin: Bool         = SMAppService.mainApp.status == .enabled
    @State private var showDictionary              = false

    // Warnings
    @State private var warningsEnabled: Bool = WarningSettings.isEnabled
    @State private var warningYellow:   Int  = WarningSettings.yellowSessions
    @State private var warningRed:      Int  = WarningSettings.redSessions

    // LLM
    @State private var llmEnabled:     Bool        = LLMSettings.isEnabled
    @State private var llmProvider:    LLMProvider = LLMSettings.provider
    @State private var llmURL:         String      = LLMSettings.serverURL
    @State private var llmKey:         String      = LLMSettings.apiKey
    @State private var llmModel:       String      = LLMSettings.model
    @State private var llmModels:      [String]    = []
    @State private var llmLoading:     Bool        = false
    @State private var llmError:       String?     = nil
    @State private var llmMinLength:   Int         = LLMSettings.minLength
    @State private var llmProxyEnabled:Bool        = LLMSettings.proxyEnabled
    @State private var llmProxyURL:    String      = LLMSettings.proxyURL
    @State private var llmPrompt:      String      = LLMSettings.systemPrompt

    // About
    @State private var showLicenses = false

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("Основные", systemImage: "gearshape") }
            llmTab
                .tabItem { Label("LLM", systemImage: "sparkles") }
            aboutTab
                .tabItem { Label("О программе", systemImage: "info.circle") }
        }
        .frame(width: 440, height: 540)
        .onAppear {
            accessibilityGranted = AXIsProcessTrusted()
            micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        }
    }

    // MARK: - Таб «Основные»

    private var generalTab: some View {
        Form {
            Section("Горячие клавиши") {
                LabeledContent("Запуск / остановка") {
                    HotkeyRecorderView(config: $hotkey) {
                        HotkeyConfig.stored = hotkey; onHotkeyChanged()
                    }
                }
                LabeledContent("Отмена записи") {
                    HotkeyRecorderView(config: $cancelHotkey) {
                        HotkeyConfig.cancelStored = cancelHotkey; onHotkeyChanged()
                    }
                }
                Text("Удержание — PTT. Короткое нажатие — переключение.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Словарь замен") {
                LabeledContent {
                    Button("Открыть…") { showDictionary = true }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Замены слов и фраз")
                        Text("Применяются до LLM-обработки")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .sheet(isPresented: $showDictionary) { DictionaryEditorView() }

            Section("Распознавание") {
                LabeledContent {
                    Stepper(pauseLabel, onIncrement: incrementPause, onDecrement: decrementPause)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Пауза между фразами")
                        Text("После паузы фраза считается завершённой")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            Section("Напоминание об отдыхе") {
                Toggle(isOn: $warningsEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Следить за дневной нагрузкой")
                        Text("Иконка меняет цвет, когда диктовок слишком много")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .onChange(of: warningsEnabled) { WarningSettings.isEnabled = $0 }
                if warningsEnabled {
                    LabeledContent {
                        Stepper("\(warningYellow) сессий", value: $warningYellow, in: 5...(warningRed - 5), step: 5)
                            .onChange(of: warningYellow) {
                                WarningSettings.yellowSessions = $0
                                NotificationCenter.default.post(name: .statsDidUpdate, object: nil)
                            }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("🟡  Жёлтая зона от")
                            Text("Усталость накапливается — лучше завершать начатое")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    LabeledContent {
                        Stepper("\(warningRed) сессий", value: $warningRed, in: (warningYellow + 5)...9999, step: 5)
                            .onChange(of: warningRed) {
                                WarningSettings.redSessions = $0
                                NotificationCenter.default.post(name: .statsDidUpdate, object: nil)
                            }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("🔴  Красная зона от")
                            Text("Слишком много за день — возьми паузу")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("Система") {
                Toggle("Приглушить звук при записи", isOn: $muteAudio)
                    .onChange(of: muteAudio) { RecordingOptions.muteAudioDuringRecording = $0 }
                Toggle("Запускать при входе в систему", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { v in
                        do { if v { try SMAppService.mainApp.register() }
                             else { try SMAppService.mainApp.unregister() } }
                        catch { launchAtLogin = SMAppService.mainApp.status == .enabled }
                    }
            }

            Section("Разрешения") {
                PermissionRow(granted: accessibilityGranted, label: "Специальные возможности",
                              url: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
                PermissionRow(granted: micGranted, label: "Микрофон",
                              url: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
            }
        }
        .formStyle(.grouped)
        .onTapGesture { NSApp.keyWindow?.makeFirstResponder(nil) }
    }

    // MARK: - Таб «LLM»

    private var llmTab: some View {
        Form {
            Section {
                Toggle(isOn: $llmEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Улучшать текст после распознавания")
                        Text("Убирает паразиты, расставляет знаки препинания, исправляет термины")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .onChange(of: llmEnabled) { LLMSettings.isEnabled = $0 }
            }

            if llmEnabled {
                Section("Подключение") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Провайдер").font(.caption).foregroundStyle(.secondary)
                        Picker("", selection: $llmProvider) {
                            ForEach(LLMProvider.allCases, id: \.self) { Text($0.label).tag($0) }
                        }
                        .labelsHidden().pickerStyle(.segmented)
                        .onChange(of: llmProvider) { v in
                            LLMSettings.provider = v
                            llmURL = LLMSettings.serverURL; llmKey = LLMSettings.apiKey
                            llmModel = LLMSettings.model; llmModels = []; llmError = nil
                        }
                    }

                    LabeledContent("Сервер") {
                        HStack(spacing: 4) {
                            TextField("", text: $llmURL)
                                .textFieldStyle(.roundedBorder)
                                .onChange(of: llmURL) { v in LLMSettings.serverURL = v; llmModels = []; llmError = nil }
                            if llmURL != llmProvider.defaultURL {
                                Button {
                                    llmURL = llmProvider.defaultURL; LLMSettings.serverURL = llmURL
                                } label: {
                                    Image(systemName: "arrow.counterclockwise").font(.system(size: 11))
                                }
                                .buttonStyle(.borderless).foregroundStyle(.secondary)
                                .help("Сбросить к значению по умолчанию")
                            }
                        }
                    }

                    LabeledContent("API ключ") {
                        SecureField("", text: $llmKey)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: llmKey) { LLMSettings.apiKey = $0 }
                    }

                    LabeledContent("Модель") {
                        HStack(spacing: 6) {
                            if llmModels.isEmpty {
                                Text(llmModel.isEmpty ? "–" : llmModel)
                                    .foregroundStyle(llmModel.isEmpty ? .secondary : .primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            } else {
                                Picker("", selection: $llmModel) {
                                    ForEach(llmModels, id: \.self) { Text($0).tag($0) }
                                }
                                .labelsHidden().frame(maxWidth: .infinity)
                                .onChange(of: llmModel) { v in guard !v.isEmpty else { return }; LLMSettings.model = v }
                            }
                            Button { loadModels() } label: {
                                Image(systemName: llmLoading ? "ellipsis" : "arrow.clockwise")
                                    .font(.system(size: 12))
                            }
                            .buttonStyle(.borderless).disabled(llmLoading || llmURL.isEmpty)
                        }
                    }
                    if let err = llmError { Text(err).font(.caption).foregroundStyle(.red) }
                }

                Section("Параметры") {
                    LabeledContent {
                        Stepper("\(llmMinLength) симв.", value: $llmMinLength, in: 10...500, step: 10)
                            .onChange(of: llmMinLength) { LLMSettings.minLength = max(10, $0) }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Минимальная длина")
                            Text("Текст короче не отправляется на обработку")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }

                    Toggle("Использовать прокси", isOn: $llmProxyEnabled)
                        .onChange(of: llmProxyEnabled) { LLMSettings.proxyEnabled = $0 }
                    if llmProxyEnabled {
                        LabeledContent("Прокси") {
                            TextField("", text: $llmProxyURL)
                                .textFieldStyle(.roundedBorder)
                                .onChange(of: llmProxyURL) { LLMSettings.proxyURL = $0 }
                        }
                    }
                }

                Section("Системный промпт") {
                    TextEditor(text: $llmPrompt)
                        .font(.system(.caption, design: .monospaced))
                        .frame(height: 90)
                        .scrollContentBackground(.hidden)
                        .onChange(of: llmPrompt) { LLMSettings.systemPrompt = $0 }
                    HStack {
                        Button("Сбросить") {
                            llmPrompt = LLMCorrector.defaultPrompt
                            LLMSettings.systemPrompt = llmPrompt
                        }
                        .buttonStyle(.borderless).foregroundStyle(.red).font(.caption)
                        Spacer()
                        Text("\(llmPrompt.count) симв.").font(.caption).foregroundStyle(.quaternary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onTapGesture { NSApp.keyWindow?.makeFirstResponder(nil) }
    }

    // MARK: - Таб «О программе»

    private var aboutTab: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable().frame(width: 48, height: 48)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Говорун").font(.headline)
                        Text("Версия \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")")
                        .font(.subheadline).foregroundStyle(.secondary)
                        Text("GigaAM v3 · Silero VAD · sherpa-onnx")
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Автор") {
                LabeledContent("Дмитрий Киселев") {
                    Link("@amidexe", destination: URL(string: "https://github.com/amidexe")!)
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Исходный код") {
                    Link("GitHub", destination: URL(string: "https://github.com/amidexe/govorun-osx")!)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Приватность") {
                LabeledContent {
                    Text("Офлайн").foregroundStyle(.secondary)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("🔒  Распознавание речи")
                        Text("Звук не покидает устройство")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                LabeledContent {
                    Text("Если включено").foregroundStyle(.secondary)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("🌐  LLM-стилизация")
                        Text("Только к серверу, который вы сами указали")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                LabeledContent {
                    Text("Keychain").foregroundStyle(.secondary)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("🔑  API-ключи")
                        Text("Хранятся в системной цепочке ключей macOS")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                LabeledContent("Лицензии компонентов") {
                    Button("Открыть…") { showLicenses = true }
                }
            }
            .sheet(isPresented: $showLicenses) { LicensesView() }
        }
        .formStyle(.grouped)
    }

    // MARK: - Helpers

    private var pauseLabel: String {
        switch pauseLength {
        case .short:  return "0.5 с"
        case .medium: return "1 с"
        case .long:   return "2 с"
        }
    }
    private func incrementPause() {
        guard pauseLength != .long   else { return }
        pauseLength = pauseLength == .short ? .medium : .long
        PauseLength.stored = pauseLength
    }
    private func decrementPause() {
        guard pauseLength != .short  else { return }
        pauseLength = pauseLength == .long ? .medium : .short
        PauseLength.stored = pauseLength
    }
    private func loadModels() {
        llmLoading = true; llmError = nil
        let snap = llmProvider
        Task {
            do {
                let models = try await LLMCorrector.shared.fetchModels()
                guard llmProvider == snap else { llmLoading = false; return }
                llmModels = models
                if llmModel.isEmpty || !models.contains(llmModel) { llmModel = models.first ?? "" }
                LLMSettings.model = llmModel
            } catch { llmError = "Не удалось подключиться к серверу" }
            llmLoading = false
        }
    }
}

// MARK: - Permission row

private struct PermissionRow: View {
    let granted: Bool
    let label: String
    let url: String

    var body: some View {
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(granted ? .green : .red)
            Text(label)
            Spacer()
            if !granted {
                Button("Открыть") { NSWorkspace.shared.open(URL(string: url)!) }
                    .buttonStyle(.borderless)
            }
        }
    }
}
