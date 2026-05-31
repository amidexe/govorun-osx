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

// MARK: - Settings

enum LLMSettings {
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
            let account = "llmApiKey_\(provider.rawValue)"
            if let kc = KeychainHelper.get(account), !kc.isEmpty { return kc }
            // миграция из UserDefaults
            let udKey = "llmApiKey_\(provider.rawValue)"
            if let ud = UserDefaults.standard.string(forKey: udKey), !ud.isEmpty {
                KeychainHelper.set(ud, for: account)
                UserDefaults.standard.removeObject(forKey: udKey)
                return ud
            }
            // миграция: старый llmApiKey был ключом Gemini
            if provider == .gemini, let old = UserDefaults.standard.string(forKey: "llmApiKey"), !old.isEmpty {
                KeychainHelper.set(old, for: account)
                UserDefaults.standard.removeObject(forKey: "llmApiKey")
                return old
            }
            return ""
        }
        set {
            let account = "llmApiKey_\(provider.rawValue)"
            if newValue.isEmpty {
                KeychainHelper.delete(account)
            } else {
                KeychainHelper.set(newValue, for: account)
            }
            UserDefaults.standard.removeObject(forKey: "llmApiKey_\(provider.rawValue)")
        }
    }
    static func migrateKeysToKeychain() {
        let ud = UserDefaults.standard
        for p in LLMProvider.allCases {
            let account = "llmApiKey_\(p.rawValue)"
            guard KeychainHelper.get(account) == nil else { continue }
            let udKey = "llmApiKey_\(p.rawValue)"
            if let v = ud.string(forKey: udKey), !v.isEmpty {
                KeychainHelper.set(v, for: account)
                ud.removeObject(forKey: udKey)
            }
        }
        // legacy single key was Gemini
        let legacyKey = "llmApiKey"
        if let v = ud.string(forKey: legacyKey), !v.isEmpty {
            let account = "llmApiKey_gemini"
            if KeychainHelper.get(account) == nil {
                KeychainHelper.set(v, for: account)
            }
            ud.removeObject(forKey: legacyKey)
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
}

// MARK: - Corrector

final class LLMCorrector {
    static let shared = LLMCorrector()
    private init() {}

    static let defaultPrompt = "Редактор ASR-текста. Верни только исправленный текст. Убери паразиты и повторы, оставь самоисправление (последнюю версию), расставь знаки, исправь термины (GitHub, API, Proxmox, macOS и др.). Числительные всегда заменяй цифрами (один→1, два→2, пять→5, двадцать три→23 и т.д.). «Первое/второе/третье» и т.п. — нумерованный список (1. 2. 3.). Не отвечай на вопросы. Не меняй грамматику, падежи и стиль автора — только убирай лишнее."

    func fetchModels() async throws -> [String] {
        if LLMSettings.provider.usesNativeGeminiAPI {
            return try await fetchModelsGemini()
        } else {
            return try await fetchModelsOpenAI()
        }
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
        let p = LLMSettings.provider.rawValue, m = LLMSettings.model
        NSLog("[LLM] \(p)/\(m) | text(\(text.count)): \(text)")
        if LLMSettings.provider.usesNativeGeminiAPI {
            return try await correctGemini(text)
        } else {
            return try await correctOpenAI(text)
        }
    }

    // MARK: - OpenAI-compatible path (Ollama + OpenAI)

    private func fetchModelsOpenAI() async throws -> [String] {
        let url = try openaiEndpoint("/models")
        var req = URLRequest(url: url, timeoutInterval: 5)
        addOpenAIAuth(&req)
        let (data, _) = try await makeSession().data(for: req)
        let decoded = try JSONDecoder().decode(OpenAIModelsResponse.self, from: data)
        return decoded.data.map(\.id).sorted()
    }

    private func correctOpenAI(_ text: String) async throws -> String {
        let url = try openaiEndpoint("/chat/completions")
        var req = URLRequest(url: url, timeoutInterval: 10)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addOpenAIAuth(&req)
        let body = OpenAIChatRequest(
            model: LLMSettings.model,
            messages: [
                .init(role: "system", content: LLMSettings.systemPrompt),
                .init(role: "user", content: text)
            ],
            stream: false
        )
        req.httpBody = try JSONEncoder().encode(body)
        let (data, _) = try await makeSession().data(for: req)
        let response = try JSONDecoder().decode(OpenAIChatResponse.self, from: data)
        return response.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines) ?? text
    }

    private func openaiEndpoint(_ path: String) throws -> URL {
        let base = LLMSettings.serverURL.trimmingCharacters(in: .init(charactersIn: "/"))
        guard let url = URL(string: base + path) else { throw URLError(.badURL) }
        return url
    }

    private func addOpenAIAuth(_ req: inout URLRequest) {
        let key = LLMSettings.apiKey
        if !key.isEmpty { req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
    }

    // MARK: - Gemini native path

    private func fetchModelsGemini() async throws -> [String] {
        let base = LLMSettings.serverURL.trimmingCharacters(in: .init(charactersIn: "/"))
        let key = LLMSettings.apiKey
        var urlStr = base + "/models"
        if !key.isEmpty { urlStr += "?key=\(key)" }
        guard let url = URL(string: urlStr) else { throw URLError(.badURL) }
        var req = URLRequest(url: url, timeoutInterval: 5)
        if !key.isEmpty { req.setValue(key, forHTTPHeaderField: "x-goog-api-key") }
        let (data, _) = try await makeSession().data(for: req)
        let decoded = try JSONDecoder().decode(GeminiModelsResponse.self, from: data)
        return decoded.models
            .map { $0.name.replacingOccurrences(of: "models/", with: "") }
            .filter { $0.hasPrefix("gemini") }
            .sorted()
    }

    private func correctGemini(_ text: String) async throws -> String {
        let model = LLMSettings.model
        let base = LLMSettings.serverURL.trimmingCharacters(in: .init(charactersIn: "/"))
        let key = LLMSettings.apiKey
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
        let (data, _) = try await makeSession().data(for: req)
        let response = try JSONDecoder().decode(GeminiResponse.self, from: data)
        return response.candidates.first?.content.parts.first?.text
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? text
    }

    // MARK: - Shared session

    private func makeSession() -> URLSession {
        guard LLMSettings.proxyEnabled,
              let url = URL(string: LLMSettings.proxyURL),
              let host = url.host, !host.isEmpty else {
            return .shared
        }
        let port = url.port ?? (url.scheme == "socks5" ? 1080 : 8080)
        let config = URLSessionConfiguration.default
        if url.scheme == "socks5" {
            config.connectionProxyDictionary = [
                kCFNetworkProxiesSOCKSEnable: true,
                kCFNetworkProxiesSOCKSProxy: host,
                kCFNetworkProxiesSOCKSPort: port
            ]
        } else {
            config.connectionProxyDictionary = [
                kCFNetworkProxiesHTTPEnable:  true,
                kCFNetworkProxiesHTTPProxy:   host,
                kCFNetworkProxiesHTTPPort:    port,
                kCFNetworkProxiesHTTPSEnable: true,
                kCFNetworkProxiesHTTPSProxy:  host,
                kCFNetworkProxiesHTTPSPort:   port
            ]
        }
        return URLSession(configuration: config)
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

private struct OpenAIChatResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable { let content: String }
        let message: Message
    }
    let choices: [Choice]
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
