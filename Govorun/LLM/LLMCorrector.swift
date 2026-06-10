import Foundation

// MARK: - Provider

enum LLMProvider: String, CaseIterable {
    case ollama = "ollama"
    case openai = "openai"
    case gemini = "gemini"

    var label: String {
        switch self {
        case .ollama: return "Ollama"
        case .openai: return "OpenAI"
        case .gemini: return "Google Gemini"
        }
    }
    var defaultURL: String {
        switch self {
        case .ollama: return "http://localhost:11434/v1"
        case .openai: return "https://api.openai.com/v1"
        case .gemini: return "https://generativelanguage.googleapis.com/v1beta"
        }
    }
    // gemini-2.5-flash-lite стабильно ~0.8с с thinkingBudget=0; 3.1 даёт 12–14с из-за инфраструктуры Google
    var defaultModel: String {
        switch self {
        case .ollama: return ""
        case .openai: return ""
        case .gemini: return "gemini-2.5-flash-lite"
        }
    }
    var keyPlaceholder: String {
        switch self {
        case .ollama: return "не требуется"
        case .openai: return "sk-..."
        case .gemini: return "Google AI Studio API Key"
        }
    }
    var usesNativeGeminiAPI: Bool { self == .gemini }
}

enum LLMApiKeyStorageState {
    case missing
    case saved
    case inaccessible
    case staleReference

    var isVisibleInSettings: Bool {
        self != .missing
    }
}

enum LLMConfigurationError: LocalizedError {
    case missingAPIKey(LLMProvider)
    case inaccessibleAPIKey(LLMProvider)
    case staleAPIKey(LLMProvider)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey(let provider):
            return "LLM включён, но ключ \(provider.label) не задан."
        case .inaccessibleAPIKey(let provider):
            return "LLM включён, но macOS не даёт доступ к ключу \(provider.label)."
        case .staleAPIKey(let provider):
            return "LLM включён, но ключ \(provider.label) не найден в Keychain."
        }
    }
}

// MARK: - Settings

enum LLMSettings {
    private static func apiKeyAccount(for provider: LLMProvider = Self.provider) -> String {
        "llmApiKey_\(provider.rawValue)"
    }

    private static func apiKeySavedFlag(for provider: LLMProvider = Self.provider) -> String {
        "llmApiKeySaved_\(provider.rawValue)"
    }

    private static func hasLegacyApiKeyInDefaults(for provider: LLMProvider = Self.provider) -> Bool {
        let providerKey = "llmApiKey_\(provider.rawValue)"
        if let value = UserDefaults.standard.string(forKey: providerKey), !value.isEmpty {
            return true
        }
        if provider == .gemini,
           let value = UserDefaults.standard.string(forKey: "llmApiKey"),
           !value.isEmpty {
            return true
        }
        return false
    }

    static var provider: LLMProvider {
        get {
            if let raw = UserDefaults.standard.string(forKey: "llmProvider"),
               let p = LLMProvider(rawValue: raw) { return p }
            // migrate from old llmEndpointType key
            let old = UserDefaults.standard.string(forKey: "llmEndpointType") ?? ""
            return old == "gemini" ? .gemini : .ollama
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "llmProvider") }
    }
    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "llmEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "llmEnabled") }
    }
    // URL, ключ и модель хранятся отдельно для каждого провайдера
    static var serverURL: String {
        get { UserDefaults.standard.string(forKey: "llmServerURL_\(provider.rawValue)") ?? provider.defaultURL }
        set { UserDefaults.standard.set(newValue, forKey: "llmServerURL_\(provider.rawValue)") }
    }
    static var apiKey: String {
        get {
            let account = apiKeyAccount()
            switch KeychainHelper.getResult(account) {
            case .value(let kc) where !kc.isEmpty:
                UserDefaults.standard.set(true, forKey: apiKeySavedFlag())
                return kc
            case .accessDenied:
                UserDefaults.standard.set(true, forKey: apiKeySavedFlag())
                return ""
            case .value, .missing, .error:
                break
            }
            // миграция из UserDefaults
            let udKey = "llmApiKey_\(provider.rawValue)"
            if let ud = UserDefaults.standard.string(forKey: udKey), !ud.isEmpty {
                if KeychainHelper.set(ud, for: account) == errSecSuccess {
                    UserDefaults.standard.set(true, forKey: apiKeySavedFlag())
                    UserDefaults.standard.removeObject(forKey: udKey)
                    return ud
                }
            }
            // миграция: старый llmApiKey был ключом Gemini
            if provider == .gemini, let old = UserDefaults.standard.string(forKey: "llmApiKey"), !old.isEmpty {
                if KeychainHelper.set(old, for: account) == errSecSuccess {
                    UserDefaults.standard.set(true, forKey: apiKeySavedFlag())
                    UserDefaults.standard.removeObject(forKey: "llmApiKey")
                    return old
                }
            }
            return ""
        }
        set {
            _ = saveApiKey(newValue)
        }
    }

    @discardableResult
    static func saveApiKey(_ value: String) -> OSStatus {
        let account = apiKeyAccount()
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            KeychainHelper.delete(account)
            UserDefaults.standard.set(false, forKey: apiKeySavedFlag())
            UserDefaults.standard.removeObject(forKey: "llmApiKey_\(provider.rawValue)")
            return errSecSuccess
        }

        let status = KeychainHelper.set(trimmed, for: account)
        UserDefaults.standard.removeObject(forKey: "llmApiKey_\(provider.rawValue)")
        guard status == errSecSuccess else {
            UserDefaults.standard.set(false, forKey: apiKeySavedFlag())
            return status
        }
        switch KeychainHelper.getResult(account) {
        case .value(let saved) where !saved.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty:
            UserDefaults.standard.set(true, forKey: apiKeySavedFlag())
            return errSecSuccess
        case .accessDenied:
            UserDefaults.standard.set(true, forKey: apiKeySavedFlag())
            return errSecInteractionNotAllowed
        case .value, .missing:
            UserDefaults.standard.set(false, forKey: apiKeySavedFlag())
            return errSecItemNotFound
        case .error(let readStatus):
            UserDefaults.standard.set(false, forKey: apiKeySavedFlag())
            return readStatus
        }
    }

    static var hasSavedApiKeyHint: Bool {
        apiKeyStorageState.isVisibleInSettings
    }

    static var requiresApiKey: Bool {
        switch provider {
        case .ollama:
            return false
        case .openai, .gemini:
            return !isLocalServerURL(serverURL)
        }
    }

    static func ensureApiKeyReady() throws {
        if let error = apiKeyConfigurationError() {
            throw error
        }
    }

    static func apiKeyForRequest() throws -> String? {
        guard requiresApiKey else {
            let optionalKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            return optionalKey.isEmpty ? nil : optionalKey
        }

        let account = apiKeyAccount()
        switch KeychainHelper.getResult(account) {
        case .value(let value):
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                UserDefaults.standard.set(false, forKey: apiKeySavedFlag())
                throw LLMConfigurationError.missingAPIKey(provider)
            }
            UserDefaults.standard.set(true, forKey: apiKeySavedFlag())
            return trimmed
        case .accessDenied:
            UserDefaults.standard.set(true, forKey: apiKeySavedFlag())
            throw LLMConfigurationError.inaccessibleAPIKey(provider)
        case .missing:
            let migrated = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if !migrated.isEmpty {
                UserDefaults.standard.set(true, forKey: apiKeySavedFlag())
                return migrated
            }
            if let error = apiKeyConfigurationError() {
                throw error
            }
            throw LLMConfigurationError.missingAPIKey(provider)
        case .error:
            UserDefaults.standard.set(true, forKey: apiKeySavedFlag())
            throw LLMConfigurationError.inaccessibleAPIKey(provider)
        }
    }

    static func apiKeyConfigurationError() -> LLMConfigurationError? {
        guard requiresApiKey else { return nil }

        switch apiKeyStorageState {
        case .saved:
            return nil
        case .missing:
            return .missingAPIKey(provider)
        case .inaccessible:
            return .inaccessibleAPIKey(provider)
        case .staleReference:
            return .staleAPIKey(provider)
        }
    }

    static var lastErrorMessage: String? {
        get { UserDefaults.standard.string(forKey: "llmLastErrorMessage") }
        set {
            if let newValue, !newValue.isEmpty {
                UserDefaults.standard.set(newValue, forKey: "llmLastErrorMessage")
            } else {
                UserDefaults.standard.removeObject(forKey: "llmLastErrorMessage")
            }
        }
    }

    static var apiKeyStorageState: LLMApiKeyStorageState {
        let savedFlag = UserDefaults.standard.bool(forKey: apiKeySavedFlag())
        switch KeychainHelper.status(apiKeyAccount()) {
        case .present:
            return .saved
        case .accessDenied:
            return .inaccessible
        case .missing:
            if hasLegacyApiKeyInDefaults() { return .saved }
            return savedFlag ? .staleReference : .missing
        case .error:
            return savedFlag ? .inaccessible : .missing
        }
    }

    static func migrateKeysToKeychain() {
        let ud = UserDefaults.standard
        for p in LLMProvider.allCases {
            let account = apiKeyAccount(for: p)
            guard KeychainHelper.get(account) == nil else { continue }
            let udKey = "llmApiKey_\(p.rawValue)"
            if let v = ud.string(forKey: udKey), !v.isEmpty {
                if KeychainHelper.set(v, for: account) == errSecSuccess {
                    ud.set(true, forKey: apiKeySavedFlag(for: p))
                    ud.removeObject(forKey: udKey)
                }
            }
        }
        // legacy single key was Gemini
        let legacyKey = "llmApiKey"
        if let v = ud.string(forKey: legacyKey), !v.isEmpty {
            let account = apiKeyAccount(for: .gemini)
            let status: OSStatus
            if KeychainHelper.get(account) == nil {
                status = KeychainHelper.set(v, for: account)
            } else {
                status = errSecSuccess
            }
            if status == errSecSuccess {
                ud.set(true, forKey: apiKeySavedFlag(for: .gemini))
                ud.removeObject(forKey: legacyKey)
            }
        }
    }

    static var model: String {
        get { UserDefaults.standard.string(forKey: "llmModel_\(provider.rawValue)") ?? provider.defaultModel }
        set { UserDefaults.standard.set(newValue, forKey: "llmModel_\(provider.rawValue)") }
    }
    static var systemPrompt: String {
        get { UserDefaults.standard.string(forKey: "llmSystemPrompt") ?? LLMCorrector.defaultPrompt }
        set { UserDefaults.standard.set(newValue, forKey: "llmSystemPrompt") }
    }
    // Минимальная длина текста для обработки (символов). Короче — пропускаем.
    static var minLength: Int {
        get {
            let v = UserDefaults.standard.integer(forKey: "llmMinLength")
            return v == 0 ? 80 : v
        }
        set { UserDefaults.standard.set(newValue, forKey: "llmMinLength") }
    }
    static var proxyEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "llmProxyEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "llmProxyEnabled") }
    }
    static var proxyURL: String {
        get { UserDefaults.standard.string(forKey: "llmProxyURL") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "llmProxyURL") }
    }

    private static func isLocalServerURL(_ raw: String) -> Bool {
        guard let host = URL(string: raw)?.host?.lowercased() else { return false }
        return host == "localhost" || host == "127.0.0.1" || host == "::1"
    }
}

// MARK: - Corrector

final class LLMCorrector {
    static let shared = LLMCorrector()
    private init() {}

    static let defaultPrompt = "Редактор ASR-текста. Верни только исправленный текст. Убери паразиты и повторы, оставь самоисправление (последнюю версию), расставь знаки, исправь термины (GitHub, API, Proxmox, macOS и др.). Числительные всегда заменяй цифрами (один→1, два→2, пять→5, двадцать три→23 и т.д.). «Первое/второе/третье» и т.п. — нумерованный список (1. 2. 3.). Не отвечай на вопросы. Не меняй грамматику, падежи и стиль автора — только убирай лишнее."

    func fetchModels() async throws -> [String] {
        try LLMSettings.ensureApiKeyReady()
        if LLMSettings.provider.usesNativeGeminiAPI {
            return try await fetchModelsGemini()
        } else {
            return try await fetchModelsOpenAI()
        }
    }

    func checkConnection() async throws -> String {
        guard !LLMSettings.model.isEmpty else {
            throw LLMSetupError("Модель LLM не выбрана.")
        }
        try LLMSettings.ensureApiKeyReady()
        if LLMSettings.provider.usesNativeGeminiAPI {
            try await checkGeminiConnection()
        } else if shouldUseOpenAIResponsesAPI {
            try await checkOpenAIResponsesConnection()
        } else {
            try await checkOpenAIChatConnection()
        }
        return "\(LLMSettings.provider.label): соединение работает, модель \(LLMSettings.model) отвечает."
    }

    func correct(_ text: String) async throws -> String {
        guard !LLMSettings.model.isEmpty else {
            NSLog("[LLM] skip: no model set")
            return text
        }
        guard text.count >= LLMSettings.minLength else {
            NSLog("[LLM] skip: too short (%d < %d)", text.count, LLMSettings.minLength)
            return text
        }
        try LLMSettings.ensureApiKeyReady()
        let p = LLMSettings.provider.rawValue, m = LLMSettings.model
        NSLog("[LLM] %@/%@ | text length: %d", p, m, text.count)
        if LLMSettings.provider.usesNativeGeminiAPI {
            return try await correctGemini(text)
        } else {
            return try await correctOpenAI(text)
        }
    }

    // MARK: - OpenAI-compatible path (Ollama + local servers)

    private func fetchModelsOpenAI() async throws -> [String] {
        let url = try openaiEndpoint("/models")
        var req = URLRequest(url: url, timeoutInterval: 5)
        try addOpenAIAuth(&req)
        let data = try await validatedData(for: req, provider: LLMSettings.provider)
        let decoded = try JSONDecoder().decode(OpenAIModelsResponse.self, from: data)
        return decoded.data.map(\.id).sorted()
    }

    private func correctOpenAI(_ text: String) async throws -> String {
        if shouldUseOpenAIResponsesAPI {
            return try await correctOpenAIResponses(text)
        }
        return try await correctOpenAIChat(text)
    }

    private func correctOpenAIResponses(_ text: String) async throws -> String {
        let url = try openaiEndpoint("/responses")
        var req = URLRequest(url: url, timeoutInterval: 20)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        try addOpenAIAuth(&req)
        let body = OpenAIResponsesRequest(
            model: LLMSettings.model,
            instructions: LLMSettings.systemPrompt,
            input: text,
            stream: false,
            store: false,
            max_output_tokens: nil
        )
        req.httpBody = try JSONEncoder().encode(body)
        let data = try await validatedData(for: req, provider: .openai)
        let response = try JSONDecoder().decode(OpenAIResponsesResponse.self, from: data)
        if let corrected = response.resolvedText?.trimmingCharacters(in: .whitespacesAndNewlines),
           !corrected.isEmpty {
            return corrected
        }
        return text
    }

    private func checkOpenAIResponsesConnection() async throws {
        let url = try openaiEndpoint("/responses")
        var req = URLRequest(url: url, timeoutInterval: 12)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        try addOpenAIAuth(&req)
        let body = OpenAIResponsesRequest(
            model: LLMSettings.model,
            instructions: "Return exactly: OK",
            input: "OK",
            stream: false,
            store: false,
            max_output_tokens: 16
        )
        req.httpBody = try JSONEncoder().encode(body)
        _ = try await validatedData(for: req, provider: .openai)
    }

    private func correctOpenAIChat(_ text: String) async throws -> String {
        let url = try openaiEndpoint("/chat/completions")
        var req = URLRequest(url: url, timeoutInterval: 10)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        try addOpenAIAuth(&req)
        let body = OpenAIChatRequest(
            model: LLMSettings.model,
            messages: [
                .init(role: "system", content: LLMSettings.systemPrompt),
                .init(role: "user", content: text)
            ],
            stream: false
        )
        req.httpBody = try JSONEncoder().encode(body)
        let data = try await validatedData(for: req, provider: LLMSettings.provider)
        let response = try JSONDecoder().decode(OpenAIChatResponse.self, from: data)
        return response.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines) ?? text
    }

    private func checkOpenAIChatConnection() async throws {
        let url = try openaiEndpoint("/chat/completions")
        var req = URLRequest(url: url, timeoutInterval: 12)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        try addOpenAIAuth(&req)
        let body = OpenAIChatRequest(
            model: LLMSettings.model,
            messages: [
                .init(role: "system", content: "Return exactly: OK"),
                .init(role: "user", content: "OK")
            ],
            stream: false
        )
        req.httpBody = try JSONEncoder().encode(body)
        _ = try await validatedData(for: req, provider: LLMSettings.provider)
    }

    private var shouldUseOpenAIResponsesAPI: Bool {
        guard LLMSettings.provider == .openai,
              let host = URL(string: LLMSettings.serverURL)?.host?.lowercased() else {
            return false
        }
        return host == "api.openai.com"
    }

    private func openaiEndpoint(_ path: String) throws -> URL {
        let base = LLMSettings.serverURL.trimmingCharacters(in: .init(charactersIn: "/"))
        guard let url = URL(string: base + path) else { throw URLError(.badURL) }
        return url
    }

    private func addOpenAIAuth(_ req: inout URLRequest) throws {
        if let key = try LLMSettings.apiKeyForRequest(), !key.isEmpty {
            req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
    }

    // MARK: - Gemini native path

    private func fetchModelsGemini() async throws -> [String] {
        let base = LLMSettings.serverURL.trimmingCharacters(in: .init(charactersIn: "/"))
        let key = try LLMSettings.apiKeyForRequest() ?? ""
        var urlStr = base + "/models"
        if !key.isEmpty { urlStr += "?key=\(key)" }
        guard let url = URL(string: urlStr) else { throw URLError(.badURL) }
        var req = URLRequest(url: url, timeoutInterval: 5)
        if !key.isEmpty { req.setValue(key, forHTTPHeaderField: "x-goog-api-key") }
        let data = try await validatedData(for: req, provider: .gemini)
        let decoded = try JSONDecoder().decode(GeminiModelsResponse.self, from: data)
        return decoded.models
            .map { $0.name.replacingOccurrences(of: "models/", with: "") }
            .filter { $0.hasPrefix("gemini") }
            .sorted()
    }

    private func correctGemini(_ text: String) async throws -> String {
        let model = LLMSettings.model
        let base = LLMSettings.serverURL.trimmingCharacters(in: .init(charactersIn: "/"))
        let key = try LLMSettings.apiKeyForRequest() ?? ""
        var urlStr = base + "/models/\(model):generateContent"
        if !key.isEmpty { urlStr += "?key=\(key)" }
        guard let url = URL(string: urlStr) else { throw URLError(.badURL) }
        var req = URLRequest(url: url, timeoutInterval: 10)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !key.isEmpty { req.setValue(key, forHTTPHeaderField: "x-goog-api-key") }
        let body = GeminiRequest(
            systemInstruction: .init(parts: [.init(text: LLMSettings.systemPrompt)]),
            contents: [.init(role: "user", parts: [.init(text: text)])],
            // thinkingBudget: 0 отключает "мышление" у Gemini 2.5, без него Flash-Lite думает 10–15с
            generationConfig: .init(thinkingConfig: .init(thinkingBudget: 0))
        )
        req.httpBody = try JSONEncoder().encode(body)
        let data = try await validatedData(for: req, provider: .gemini)
        let response = try JSONDecoder().decode(GeminiResponse.self, from: data)
        return response.candidates.first?.content.parts.first?.text
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? text
    }

    private func checkGeminiConnection() async throws {
        let model = LLMSettings.model
        let base = LLMSettings.serverURL.trimmingCharacters(in: .init(charactersIn: "/"))
        let key = try LLMSettings.apiKeyForRequest() ?? ""
        var urlStr = base + "/models/\(model):generateContent"
        if !key.isEmpty { urlStr += "?key=\(key)" }
        guard let url = URL(string: urlStr) else { throw URLError(.badURL) }
        var req = URLRequest(url: url, timeoutInterval: 12)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !key.isEmpty { req.setValue(key, forHTTPHeaderField: "x-goog-api-key") }
        let body = GeminiRequest(
            systemInstruction: .init(parts: [.init(text: "Return exactly: OK")]),
            contents: [.init(role: "user", parts: [.init(text: "OK")])],
            generationConfig: .init(thinkingConfig: .init(thinkingBudget: 0))
        )
        req.httpBody = try JSONEncoder().encode(body)
        _ = try await validatedData(for: req, provider: .gemini)
    }

    // MARK: - Shared session

    private func makeSession() -> URLSession {
        LLMProxy.makeSession(proxyEnabled: LLMSettings.proxyEnabled, proxyURL: LLMSettings.proxyURL)
    }

    private func validatedData(for request: URLRequest, provider: LLMProvider) async throws -> Data {
        let (data, response) = try await makeSession().data(for: request)
        guard let http = response as? HTTPURLResponse else { return data }
        guard (200..<300).contains(http.statusCode) else {
            throw LLMHTTPError(
                provider: provider,
                statusCode: http.statusCode,
                message: decodeErrorMessage(from: data) ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            )
        }
        return data
    }

    private func decodeErrorMessage(from data: Data) -> String? {
        if let decoded = try? JSONDecoder().decode(OpenAIErrorResponse.self, from: data),
           let message = decoded.error.message?.trimmingCharacters(in: .whitespacesAndNewlines),
           !message.isEmpty {
            return message
        }
        if let decoded = try? JSONDecoder().decode(GeminiErrorResponse.self, from: data),
           let message = decoded.error.message?.trimmingCharacters(in: .whitespacesAndNewlines),
           !message.isEmpty {
            return message
        }
        guard let raw = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else {
            return nil
        }
        return raw.count > 240 ? String(raw.prefix(240)) + "…" : raw
    }
}

private struct LLMHTTPError: LocalizedError {
    let provider: LLMProvider
    let statusCode: Int
    let message: String

    var errorDescription: String? {
        "\(provider.label): HTTP \(statusCode). \(message)"
    }
}

private struct LLMSetupError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? {
        message
    }
}

// MARK: - OpenAI Codable

private struct OpenAIModelsResponse: Decodable {
    struct Model: Decodable { let id: String }
    let data: [Model]
}

private struct OpenAIChatRequest: Encodable {
    struct Message: Encodable { let role: String; let content: String }
    let model: String
    let messages: [Message]
    let stream: Bool
}

private struct OpenAIResponsesRequest: Encodable {
    let model: String
    let instructions: String
    let input: String
    let stream: Bool
    let store: Bool
    let max_output_tokens: Int?
}

private struct OpenAIResponsesResponse: Decodable {
    struct OutputItem: Decodable {
        struct ContentItem: Decodable {
            let type: String?
            let text: String?
        }
        let type: String?
        let content: [ContentItem]?
    }

    let output_text: String?
    let output: [OutputItem]?

    var resolvedText: String? {
        if let output_text, !output_text.isEmpty {
            return output_text
        }
        return output?
            .lazy
            .compactMap { item in
                item.content?.first { content in
                    guard let text = content.text else { return false }
                    return !text.isEmpty
                }?.text
            }
            .first
    }
}

private struct OpenAIChatResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable { let content: String }
        let message: Message
    }
    let choices: [Choice]
}

private struct OpenAIErrorResponse: Decodable {
    struct APIError: Decodable {
        let message: String?
    }
    let error: APIError
}

// MARK: - Gemini Codable

private struct GeminiModelsResponse: Decodable {
    struct GeminiModel: Decodable { let name: String }
    let models: [GeminiModel]
}

private struct GeminiRequest: Encodable {
    struct Part: Encodable { let text: String }
    struct Content: Encodable { let parts: [Part] }
    struct ContentWithRole: Encodable { let role: String; let parts: [Part] }
    struct ThinkingConfig: Encodable { let thinkingBudget: Int }
    struct GenerationConfig: Encodable { let thinkingConfig: ThinkingConfig }

    let systemInstruction: Content
    let contents: [ContentWithRole]
    let generationConfig: GenerationConfig
}

private struct GeminiResponse: Decodable {
    struct Part: Decodable { let text: String }
    struct Content: Decodable { let parts: [Part] }
    struct Candidate: Decodable { let content: Content }
    let candidates: [Candidate]
}

private struct GeminiErrorResponse: Decodable {
    struct APIError: Decodable {
        let message: String?
    }
    let error: APIError
}
