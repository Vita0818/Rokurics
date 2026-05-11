//
//  KeychainStore.swift
//  Rokurics
//
//  Created by Codex on 2026/5/10.
//

import Foundation
import Security

enum KeychainStoreError: LocalizedError {
    case invalidValue
    case unhandledStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidValue:
            return "Keychain value is invalid."
        case .unhandledStatus(let status):
            return "Keychain operation failed: \(status)"
        }
    }
}

struct KeychainStore {
    private let service: String

    init(service: String = SecureMacConnectionSettings.keychainService) {
        self.service = service
    }

    func save(_ value: String, account: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainStoreError.invalidValue
        }

        let query = baseQuery(account: account)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecSuccess {
            return
        }

        guard status == errSecItemNotFound else {
            throw KeychainStoreError.unhandledStatus(status)
        }

        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainStoreError.unhandledStatus(addStatus)
        }
    }

    func load(account: String) throws -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw KeychainStoreError.unhandledStatus(status)
        }

        guard let data = item as? Data, let value = String(data: data, encoding: .utf8) else {
            throw KeychainStoreError.invalidValue
        }

        return value
    }

    func delete(account: String) throws {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainStoreError.unhandledStatus(status)
        }
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
