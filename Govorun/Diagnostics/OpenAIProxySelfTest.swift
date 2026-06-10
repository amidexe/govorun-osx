import Foundation

enum OpenAIProxySelfTest {
    static func runIfRequested() {
        let env = ProcessInfo.processInfo.environment
        guard env["GOVORUN_OPENAI_PROXY_SELFTEST"] == "1" else { return }

        let proxyURL = env["GOVORUN_OPENAI_PROXY_URL"] ?? LLMSettings.proxyURL
        let apiKey = env["GOVORUN_OPENAI_API_KEY"] ?? env["OPENAI_API_KEY"]
        let usesRealKey = apiKey?.isEmpty == false
        let bearer = usesRealKey ? apiKey! : "govorun-invalid-proxy-smoke"

        guard !proxyURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            fail("proxy URL is empty")
        }
        guard let url = URL(string: "https://api.openai.com/v1/models") else {
            fail("bad OpenAI smoke URL")
        }

        let session = LLMProxy.makeSession(proxyEnabled: true, proxyURL: proxyURL)
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")

        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<Int, Error>?
        let task = session.dataTask(with: request) { _, response, error in
            if let error {
                result = .failure(error)
            } else if let http = response as? HTTPURLResponse {
                result = .success(http.statusCode)
            } else {
                result = .failure(URLError(.badServerResponse))
            }
            semaphore.signal()
        }
        task.resume()

        if semaphore.wait(timeout: .now() + 20) == .timedOut {
            task.cancel()
            fail("OpenAI proxy request timed out")
        }

        switch result {
        case .success(let status) where usesRealKey && (200..<300).contains(status):
            print("openai proxy smoke checks: ok")
            exit(0)
        case .success(401) where !usesRealKey:
            print("openai proxy smoke checks: ok")
            exit(0)
        case .success(let status):
            let expectation = usesRealKey ? "2xx" : "401 with dummy key"
            fail("unexpected HTTP \(status), expected \(expectation)")
        case .failure(let error):
            fail(error.localizedDescription)
        case .none:
            fail("request finished without a result")
        }
    }

    private static func fail(_ message: String) -> Never {
        fputs("openai proxy smoke failed: \(message)\n", stderr)
        exit(1)
    }
}
