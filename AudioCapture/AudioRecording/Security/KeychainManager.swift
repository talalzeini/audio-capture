//
//  KeychainManager.swift
//  AudioCapture
//
//  Created by Talal El Zeini on 3/11/26.
//

import Foundation
import Security

enum KeychainManager {
    enum Keys {
        static let openAIAPIKey = "com.audiocapture.openai-api-key"
    }

    enum KeychainError: LocalizedError {
        case unhandledError(status: OSStatus)
        case dataEncodingFailed
        case unexpectedDataFormat

        var errorDescription: String? {
            switch self {
            case .unhandledError(let status):
                return "Keychain error (OSStatus \(status))"
            case .dataEncodingFailed:
                return "Could not encode value as UTF-8 data."
            case .unexpectedDataFormat:
                return "Value retrieved from Keychain was not valid UTF-8."
            }
        }
    }

    static func save(_ value: String, forKey key: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.dataEncodingFailed
        }

        let query = baseQuery(for: key)
        let attributes: [CFString: Any] = [
            kSecValueData:       data,
            kSecAttrAccessible:  kSecAttrAccessibleAfterFirstUnlock,
        ]

        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

        if status == errSecItemNotFound {
            var newItem = query
            newItem[kSecValueData]      = data
            newItem[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlock
            status = SecItemAdd(newItem as CFDictionary, nil)
        }

        guard status == errSecSuccess else {
            throw KeychainError.unhandledError(status: status)
        }
    }

    static func read(forKey key: String) throws -> String? {
        var query = baseQuery(for: key)
        query[kSecReturnData]   = true
        query[kSecMatchLimit]   = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data,
                  let value = String(data: data, encoding: .utf8) else {
                throw KeychainError.unexpectedDataFormat
            }
            return value
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.unhandledError(status: status)
        }
    }

    // Removes the item stored under key. No-op if no item exists.
    static func delete(forKey key: String) {
        SecItemDelete(baseQuery(for: key) as CFDictionary)
    }

    // MARK: - Private

    private static func baseQuery(for key: String) -> [CFString: Any] {
        [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: "com.audiocapture",
            kSecAttrAccount: key,
        ]
    }
}
