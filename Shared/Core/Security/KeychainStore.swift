//
//  KeychainStore.swift
//  SecurityIslas
//
//  Envoltura mínima del Keychain. `accessGroup` queda listo para compartir la
//  sesión con widgets, Notification Service Extension e intents cuando se
//  agreguen esos targets (requiere el entitlement de Keychain Sharing).
//

import Foundation
import Security

nonisolated enum KeychainError: Error, Sendable {
    case unhandled(OSStatus)
}

nonisolated struct KeychainStore: Sendable {
    let service: String
    let accessGroup: String?

    static let app = KeychainStore(service: "app.security.islasgower", accessGroup: AppInfo.keychainAccessGroup)

    func data(for key: String) -> Data? {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    func set(_ data: Data, for key: String) throws {
        let query = baseQuery(for: key)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            for (key, value) in attributes {
                insert[key] = value
            }
            let addStatus = SecItemAdd(insert as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError.unhandled(addStatus) }
        } else if status != errSecSuccess {
            throw KeychainError.unhandled(status)
        }
    }

    func delete(_ key: String) {
        _ = SecItemDelete(baseQuery(for: key) as CFDictionary)
    }

    // MARK: - Codable

    func value<T: Decodable>(_ type: T.Type, for key: String) -> T? {
        guard let data = data(for: key) else { return nil }
        return try? JSONCoding.decoder().decode(T.self, from: data)
    }

    func setValue<T: Encodable>(_ value: T, for key: String) throws {
        try set(JSONCoding.encoder().encode(value), for: key)
    }

    private func baseQuery(for key: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }
}
