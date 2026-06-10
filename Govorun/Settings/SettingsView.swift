import SwiftUI
import ApplicationServices
import AVFoundation
import ServiceManagement

private enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case llm
    case stats

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "Основные"
        case .llm:     return "LLM"
        case .stats:   return "Статистика"
        }
    }

    var systemImage: String {
        switch self {
        case .general: return "gearshape"
        case .llm:     return "sparkles"
        case .stats:   return "chart.bar"
        }
    }
}

struct SettingsView: View {
    var onHotkeyChanged: () -> Void = {}

    @EnvironmentObject var engine: AudioEngine

    @State private var selectedTab: SettingsTab = .general

    // General
    @State private var accessibilityGranted = AXIsProcessTrusted()
    @State private var micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    @State private var pauseLength:   PauseLength  = PauseLength.stored
    @State private var hotkey:        HotkeyConfig = HotkeyConfig.stored
    @State private var cancelHotkey:  HotkeyConfig = HotkeyConfig.cancelStored ?? HotkeyConfig.defaultCancel
    @State private var muteAudio:     Bool         = RecordingOptions.muteAudioDuringRecording
    @State private var playSounds:    Bool         = RecordingOptions.playRecordingSounds
    @State private var maxRecMinutes: Int          = RecordingOptions.maxRecordingMinutes
    @State private var launchAtLogin: Bool         = SMAppService.mainApp.status == .enabled
    @State private var showDictionary              = false

    // Warnings (зоны по минутам речи за день)
    @State private var warningsEnabled: Bool = WarningSettings.isEnabled
    @State private var warningYellow:   Int  = WarningSettings.yellowMinutes
    @State private var warningRed:      Int  = WarningSettings.redMinutes

    // LLM
    @State private var llmEnabled:      Bool        = LLMSettings.isEnabled
    @State private var llmProvider:     LLMProvider = LLMSettings.provider
    @State private var llmURL:          String      = LLMSettings.serverURL
    @State private var llmKey:          String      = LLMSettings.apiKey
    @State private var llmModel:        String      = LLMSettings.model
    @State private var llmModels:       [String]    = []
    @State private var llmLoading:      Bool        = false
    @State private var llmError:        String?     = nil
    @State private var llmMinLength:    Int         = LLMSettings.minLength
    @State private var llmProxyEnabled: Bool        = LLMSettings.proxyEnabled
    @State private var llmProxyURL:     String      = LLMSettings.proxyURL
    @State private var llmPrompt:       String      = LLMSettings.systemPrompt

    // About
    @State private var showLicenses = false
    @State private var showAbout    = false

    var body: some View {
        VStack(spacing: 0) {
            SettingsTabBar(selection: $selectedTab)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

            Divider()

            Group {
                switch selectedTab {
                case .general:
                    generalTab
                case .llm:
                    llmTab
                case .stats:
                    StatsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(width: 460, height: 560)
        .onAppear {
            accessibilityGranted = AXIsProcessTrusted()
            micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        }
        .sheet(isPresented: $showDictionary) { DictionaryEditorView() }
        .sheet(isPresented: $showAbout) { aboutSheet }
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
            }

            SettingsSection("Словарь замен") {
                SettingsRow("Замены слов и фраз", subtitle: "Применяются до LLM-обработки") {
                    Button("Открыть…") { showDictionary = true }
                }
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
                        title: "Следить за дневной нагрузкой",
                        subtitle: "Иконка меняет цвет, когда диктовок слишком много"
                    )
                }
                .onChange(of: warningsEnabled) { WarningSettings.isEnabled = $0 }

                if warningsEnabled {
                    SettingsRow("Жёлтая зона от", subtitle: "Минут речи за день, после которых копится усталость") {
                        Stepper("\(warningYellow) мин", value: $warningYellow, in: yellowRange, step: 5)
                            .frame(width: 116, alignment: .trailing)
                            .onChange(of: warningYellow) {
                                warningYellow = min($0, warningRed - 5)
                                WarningSettings.yellowMinutes = warningYellow
                                NotificationCenter.default.post(name: .statsDidUpdate, object: nil)
                            }
                    }
                    SettingsRow("Красная зона от", subtitle: "Слишком много речи за день — возьми паузу") {
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
                    url: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
                )
                PermissionRow(
                    granted: micGranted,
                    label: "Микрофон",
                    url: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
                )
            }

            SettingsSection {
                SettingsRow("О программе", subtitle: "Версия, автор, приватность, лицензии") {
                    Button("Открыть…") { showAbout = true }
                }
            }
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
                .onChange(of: llmEnabled) { LLMSettings.isEnabled = $0 }
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
                            llmKey = LLMSettings.apiKey
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
                                }
                            if llmURL != llmProvider.defaultURL {
                                Button {
                                    llmURL = llmProvider.defaultURL
                                    LLMSettings.serverURL = llmURL
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

                    SettingsRow("API ключ") {
                        SecureField("", text: $llmKey)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 220)
                            .onChange(of: llmKey) { LLMSettings.apiKey = $0 }
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
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                        )
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

    // MARK: - «О программе» (sheet из «Основных»)

    private var aboutSheet: some View {
        VStack(spacing: 0) {
            HStack {
                Text("О программе").font(.headline)
                Spacer()
                Button("Закрыть") { showAbout = false }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            Divider()
            aboutTab
        }
        .frame(width: 440, height: 470)
        .sheet(isPresented: $showLicenses) { LicensesView() }
    }

    private var aboutTab: some View {
        SettingsPage {
            SettingsSection {
                HStack(spacing: 12) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 48, height: 48)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Говорун").font(.headline)
                        Text("Версия \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("GigaAM v3 · Silero VAD · sherpa-onnx")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.vertical, 4)
            }

            SettingsSection("Автор") {
                SettingsRow("Дмитрий Киселев") {
                    Link("@amidexe", destination: URL(string: "https://github.com/amidexe")!)
                        .foregroundStyle(.secondary)
                }
                SettingsRow("Исходный код") {
                    Link("GitHub", destination: URL(string: "https://github.com/amidexe/govorun-osx")!)
                        .foregroundStyle(.secondary)
                }
            }

            SettingsSection("Приватность") {
                SettingsRow("Распознавание речи", subtitle: "Звук не покидает устройство") {
                    Text("Офлайн").foregroundStyle(.secondary)
                }
                SettingsRow("LLM-стилизация", subtitle: "Только к серверу, который вы сами указали") {
                    Text("Если включено").foregroundStyle(.secondary)
                }
                SettingsRow("API-ключи", subtitle: "Хранятся в системной цепочке ключей macOS") {
                    Text("Keychain").foregroundStyle(.secondary)
                }
            }

            SettingsSection {
                SettingsRow("Лицензии компонентов") {
                    Button("Открыть…") { showLicenses = true }
                }
            }
        }
    }

    // MARK: - Helpers

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
            } catch {
                llmError = "Не удалось подключиться к серверу"
            }
            llmLoading = false
        }
    }
}

// MARK: - Stable settings layout

private struct SettingsTabBar: View {
    @Binding var selection: SettingsTab

    var body: some View {
        HStack(spacing: 4) {
            ForEach(SettingsTab.allCases) { tab in
                Button {
                    selection = tab
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tab.systemImage)
                        Text(tab.title)
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(selection == tab ? Color.accentColor : Color.primary)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(selection == tab ? Color.accentColor.opacity(0.16) : Color.clear)
                )
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(NSColor.windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
        )
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
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(NSColor.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
