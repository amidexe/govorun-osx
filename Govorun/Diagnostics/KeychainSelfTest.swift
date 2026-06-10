import Foundation
import Security

enum KeychainSelfTest {
    static func runIfRequested() {
        guard ProcessInfo.processInfo.environment["GOVORUN_KEYCHAIN_SELFTEST"] == "1" else { return }

        let account = "llmApiKey_regression_test_\(UUID().uuidString)"
        func fail(_ message: String) -> Never {
            fputs("keychain regression failed: \(message)\n", stderr)
            _ = KeychainHelper.deleteStatus(account)
            exit(1)
        }

        func message(for status: OSStatus) -> String {
            if let text = SecCopyErrorMessageString(status, nil) as String? {
                return "\(status) \(text)"
            }
            return "\(status)"
        }

        func debugSnapshot() -> String {
            let syncVariants: [(String, Any?)] = [
                ("plain", nil),
                ("sync-true", true),
                ("sync-false", false),
                ("sync-any", kSecAttrSynchronizableAny)
            ]
            let services = [
                KeychainHelper.currentService,
                "com.govorun.app.llm",
                "com.govorun.app"
            ]
            return services.flatMap { service in
                syncVariants.map { label, syncValue in
                    var query: [CFString: Any] = [
                        kSecClass: kSecClassGenericPassword,
                        kSecAttrService: service,
                        kSecAttrAccount: account,
                        kSecReturnData: true,
                        kSecMatchLimit: kSecMatchLimitOne
                    ]
                    if let syncValue {
                        query[kSecAttrSynchronizable] = syncValue
                    }
                    var result: AnyObject?
                    let status = SecItemCopyMatching(query as CFDictionary, &result)
                    let value: String
                    if let data = result as? Data,
                       let text = String(data: data, encoding: .utf8) {
                        value = text
                    } else {
                        value = "nil"
                    }
                    return "\(service)/\(label)=\(message(for: status))/\(value)"
                }
            }
            .joined(separator: "; ")
        }

        func expectSuccess(_ status: OSStatus, _ label: String) {
            guard status == errSecSuccess else {
                fail("\(label): \(message(for: status))")
            }
        }

        func expectValue(_ expected: String, _ label: String) {
            let actual = KeychainHelper.get(account)
            guard actual == expected else {
                fail("\(label): expected \(expected), got \(actual ?? "nil"); \(debugSnapshot())")
            }
        }

        func directAdd(_ value: String, synchronizable: Bool? = nil) -> OSStatus {
            var query: [CFString: Any] = [
                kSecClass: kSecClassGenericPassword,
                kSecAttrService: KeychainHelper.currentService,
                kSecAttrAccount: account,
                kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlock,
                kSecValueData: Data(value.utf8)
            ]
            if let synchronizable {
                query[kSecAttrSynchronizable] = synchronizable
            }
            return SecItemAdd(query as CFDictionary, nil)
        }

        _ = KeychainHelper.deleteStatus(account)
        guard KeychainHelper.get(account) == nil else {
            fail("initial delete did not clear test account")
        }

        expectSuccess(KeychainHelper.set("first", for: account), "save first")
        expectValue("first", "read first")

        expectSuccess(KeychainHelper.set("second", for: account), "replace with second")
        expectValue("second", "read second")

        expectSuccess(KeychainHelper.deleteStatus(account), "delete regular item")
        guard KeychainHelper.get(account) == nil else {
            fail("delete regular item did not clear account")
        }

        expectSuccess(directAdd("manual-local"), "direct local duplicate setup")
        expectSuccess(KeychainHelper.set("replaced-local", for: account), "replace direct local item")
        expectValue("replaced-local", "read replaced direct local item")
        expectSuccess(KeychainHelper.deleteStatus(account), "delete direct local item")

        let syncStatus = directAdd("manual-sync", synchronizable: true)
        if syncStatus == errSecSuccess {
            expectSuccess(KeychainHelper.set("replaced-sync", for: account), "replace direct synchronizable item")
            expectValue("replaced-sync", "read replaced synchronizable item")
            expectSuccess(KeychainHelper.deleteStatus(account), "delete direct synchronizable item")
        }

        print("keychain regression checks: ok")
        exit(0)
    }
}
