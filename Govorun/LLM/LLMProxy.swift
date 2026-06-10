import Foundation

enum LLMProxy {
    static func makeSession(proxyEnabled: Bool, proxyURL: String) -> URLSession {
        guard proxyEnabled,
              let url = URL(string: proxyURL),
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
                kCFNetworkProxiesHTTPEnable: true,
                kCFNetworkProxiesHTTPProxy: host,
                kCFNetworkProxiesHTTPPort: port,
                kCFNetworkProxiesHTTPSEnable: true,
                kCFNetworkProxiesHTTPSProxy: host,
                kCFNetworkProxiesHTTPSPort: port
            ]
        }
        return URLSession(configuration: config)
    }
}
