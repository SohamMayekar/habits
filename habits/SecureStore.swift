import Foundation
import Security

enum SecureStoreError: Error, Equatable, Sendable {
    case stringEncodingFailed
    case invalidData
    case invalidStringData
    case unhandledStatus(OSStatus)
}

struct KeychainClient: Sendable {
    var add: @Sendable ([String: Any]) -> OSStatus
    var copyMatching: @Sendable ([String: Any]) -> (OSStatus, Any?)
    var update: @Sendable ([String: Any], [String: Any]) -> OSStatus
    var delete: @Sendable ([String: Any]) -> OSStatus

    static let live = KeychainClient(
        add: { query in
            SecItemAdd(query as CFDictionary, nil)
        },
        copyMatching: { query in
            var result: AnyObject?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            return (status, result)
        },
        update: { query, attributes in
            SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        },
        delete: { query in
            SecItemDelete(query as CFDictionary)
        }
    )
}

struct SecureStore: Sendable {
    let service: String
    let accessibility: CFString

    private let client: KeychainClient

    init(
        service: String = Bundle.main.bundleIdentifier ?? "com.soham.habits.secure-store",
        accessibility: CFString = kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        client: KeychainClient = .live
    ) {
        self.service = service
        self.accessibility = accessibility
        self.client = client
    }

    func save(_ string: String, for account: String) throws {
        guard let data = string.data(using: .utf8) else {
            throw SecureStoreError.stringEncodingFailed
        }

        try save(data, for: account)
    }

    func save(_ data: Data, for account: String) throws {
        let status = client.add(baseQuery(for: account, valueData: data))

        switch status {
        case errSecSuccess:
            return
        case errSecDuplicateItem:
            let updateStatus = client.update(
                baseQuery(for: account),
                [kSecValueData as String: data]
            )
            guard updateStatus == errSecSuccess else {
                throw SecureStoreError.unhandledStatus(updateStatus)
            }
        default:
            throw SecureStoreError.unhandledStatus(status)
        }
    }

    func string(for account: String) throws -> String? {
        guard let data = try data(for: account) else {
            return nil
        }

        guard let value = String(data: data, encoding: .utf8) else {
            throw SecureStoreError.invalidStringData
        }

        return value
    }

    func data(for account: String) throws -> Data? {
        var query = baseQuery(for: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        let (status, result) = client.copyMatching(query)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data else {
                throw SecureStoreError.invalidData
            }
            return data
        case errSecItemNotFound:
            return nil
        default:
            throw SecureStoreError.unhandledStatus(status)
        }
    }

    func containsValue(for account: String) -> Bool {
        (try? data(for: account)) != nil
    }

    func removeValue(for account: String) throws {
        let status = client.delete(baseQuery(for: account))
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecureStoreError.unhandledStatus(status)
        }
    }

    func baseQuery(for account: String, valueData: Data? = nil) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: accessibility
        ]

        if let valueData {
            query[kSecValueData as String] = valueData
        }

        return query
    }
}
