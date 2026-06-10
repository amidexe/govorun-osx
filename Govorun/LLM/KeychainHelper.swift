import Foundation
import Security

enum KeychainHelper {
    private static let service = "com.govorun.app.llm.v2"
    private static let legacyServices = ["com.govorun.app.llm", "com.govorun.app"]
    static let currentService = service

    enum ItemStatus: Equatable {
        case present
        case missing
        case accessDenied
        case error(OSStatus)
    }

    enum ReadResult {
        case value(String)
        case missing
        case accessDenied
        case error(OSStatus)
    }

    static func get(_ account: String) -> String? {
        if case .value(let value) = getResult(account) {
            return value
        }
        return nil
    }

    static func getResult(_ account: String) -> ReadResult {
        var lastStatus: OSStatus = errSecItemNotFound
        for var query in readQueries(for: account) {
            query[kSecReturnData] = true
            query[kSecMatchLimit] = kSecMatchLimitOne
            var result: AnyObject?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            if status == errSecSuccess {
                guard let data = result as? Data,
                      let value = String(data: data, encoding: .utf8) else {
                    return .error(errSecDecode)
                }
                return .value(value)
            }
            if isBlocking(status) {
                return mapReadStatus(status)
            }
            if status != errSecItemNotFound {
                lastStatus = status
            }
        }
        return mapReadStatus(lastStatus)
    }

    static func status(_ account: String) -> ItemStatus {
        var lastStatus: OSStatus = errSecItemNotFound
        for var query in readQueries(for: account) {
            query[kSecMatchLimit] = kSecMatchLimitOne
            let status = SecItemCopyMatching(query as CFDictionary, nil)
            switch status {
            case errSecSuccess:
                return .present
            case errSecItemNotFound:
                continue
            case errSecAuthFailed, errSecUserCanceled, errSecInteractionNotAllowed:
                return .accessDenied
            default:
                lastStatus = status
            }
        }
        return lastStatus == errSecItemNotFound ? .missing : .error(lastStatus)
    }

    @discardableResult
    static func set(_ value: String, for account: String) -> OSStatus {
        let data = Data(value.utf8)

        let cleanupStatus = deleteStatus(account)
        if isBlocking(cleanupStatus) {
            return cleanupStatus
        }

        let addStatus = add(data, account: account)
        if addStatus == errSecSuccess {
            return verifiedStatus(expected: value, account: account)
        }
        guard addStatus == errSecDuplicateItem else {
            return addStatus
        }

        let retryAddStatus = add(data, account: account)
        if retryAddStatus == errSecSuccess {
            return verifiedStatus(expected: value, account: account)
        }
        if retryAddStatus == errSecDuplicateItem {
            let update = [kSecValueData: data] as CFDictionary
            for query in updateQueries(for: account, service: service) {
                let status = SecItemUpdate(query as CFDictionary, update)
                if status == errSecSuccess {
                    return verifiedStatus(expected: value, account: account)
                }
                if isBlocking(status) {
                    return status
                }
            }
        }
        return retryAddStatus
    }

    static func delete(_ account: String) {
        _ = deleteStatus(account)
    }

    @discardableResult
    static func deleteStatus(_ account: String) -> OSStatus {
        var result: OSStatus = errSecItemNotFound
        for query in deleteQueries(for: account) {
            let status = SecItemDelete(query as CFDictionary)
            if status == errSecSuccess {
                result = errSecSuccess
            } else if isBlocking(status) {
                return status
            } else if result != errSecSuccess, status != errSecItemNotFound {
                result = status
            }
        }
        return result
    }

    static func message(for status: OSStatus) -> String {
        if let text = SecCopyErrorMessageString(status, nil) as String? {
            return text
        }
        return "Keychain status \(status)"
    }

    private static var readableServices: [String] {
        [service]
    }

    private static var cleanupServices: [String] {
        [service] + legacyServices
    }

    private static func matchQuery(for account: String, service: String, synchronizable: Any? = nil) -> [CFString: Any] {
        var query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        if let synchronizable {
            query[kSecAttrSynchronizable] = synchronizable
        }
        return query
    }

    private static func addQuery(for account: String, data: Data) -> [CFString: Any] {
        [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecValueData:   data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlock
        ]
    }

    private static func readQueries(for account: String) -> [[CFString: Any]] {
        readableServices.flatMap { service in
            [
                matchQuery(for: account, service: service, synchronizable: nil),
                matchQuery(for: account, service: service, synchronizable: true)
            ]
        }
    }

    private static func updateQueries(for account: String, service: String) -> [[CFString: Any]] {
        [
            matchQuery(for: account, service: service, synchronizable: nil),
            matchQuery(for: account, service: service, synchronizable: true)
        ]
    }

    private static func deleteQueries(for account: String) -> [[CFString: Any]] {
        cleanupServices.flatMap { service in
            [
                matchQuery(for: account, service: service, synchronizable: nil),
                matchQuery(for: account, service: service, synchronizable: true),
                matchQuery(for: account, service: service, synchronizable: false),
                matchQuery(for: account, service: service, synchronizable: kSecAttrSynchronizableAny)
            ]
        }
    }

    private static func add(_ data: Data, account: String) -> OSStatus {
        SecItemAdd(addQuery(for: account, data: data) as CFDictionary, nil)
    }

    private static func verifiedStatus(expected: String, account: String) -> OSStatus {
        switch getResult(account) {
        case .value(let actual):
            return actual == expected ? errSecSuccess : errSecDuplicateItem
        case .missing:
            return errSecItemNotFound
        case .accessDenied:
            return errSecInteractionNotAllowed
        case .error(let status):
            return status
        }
    }

    private static func mapReadStatus(_ status: OSStatus) -> ReadResult {
        switch status {
        case errSecItemNotFound:
            return .missing
        case errSecAuthFailed, errSecUserCanceled, errSecInteractionNotAllowed:
            return .accessDenied
        default:
            return .error(status)
        }
    }

    private static func isBlocking(_ status: OSStatus) -> Bool {
        status == errSecAuthFailed ||
        status == errSecUserCanceled ||
        status == errSecInteractionNotAllowed
    }
}
