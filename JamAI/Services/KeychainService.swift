//
//  KeychainService.swift
//  JamAI
//
//  Secure storage for API keys using macOS Keychain
//

import Foundation
import Security

/// Service for securely storing and retrieving API keys from the macOS Keychain
final class KeychainService {
    static let shared = KeychainService()
    
    private let service = "com.jamai.api-keys"
    
    private init() {}
    
    // MARK: - Public API
    
    /// Save an API key to the Keychain
    /// - Parameters:
    ///   - key: The API key value
    ///   - identifier: Unique identifier for this key (e.g., "openai-api-key")
    func save(key: String, identifier: String) throws {
        guard let data = key.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }
        
        // Delete any existing key first
        try? delete(identifier: identifier)
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: identifier,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }
    
    /// Retrieve an API key from the Keychain
    /// - Parameter identifier: Unique identifier for the key
    /// - Returns: The API key value, or nil if not found
    func get(identifier: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: identifier,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let data = result as? Data,
              let key = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        return key
    }
    
    /// Delete an API key from the Keychain
    /// - Parameter identifier: Unique identifier for the key
    func delete(identifier: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: identifier
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }
    
    /// Check if an API key exists in the Keychain
    /// - Parameter identifier: Unique identifier for the key
    /// - Returns: True if the key exists
    func exists(identifier: String) -> Bool {
        return get(identifier: identifier) != nil
    }
    
    // MARK: - Convenience Methods for Providers
    
    /// Get API key for a specific provider
    func getKey(for provider: AIProvider) -> String? {
        guard let identifier = provider.keychainIdentifier else { return nil }
        return get(identifier: identifier)
    }
    
    /// Save API key for a specific provider
    func saveKey(_ key: String, for provider: AIProvider) throws {
        guard let identifier = provider.keychainIdentifier else {
            throw KeychainError.noIdentifier
        }
        try save(key: key, identifier: identifier)
    }
    
    /// Delete API key for a specific provider
    func deleteKey(for provider: AIProvider) throws {
        guard let identifier = provider.keychainIdentifier else {
            throw KeychainError.noIdentifier
        }
        try delete(identifier: identifier)
    }
    
    /// Check if API key exists for a specific provider
    func hasKey(for provider: AIProvider) -> Bool {
        guard let identifier = provider.keychainIdentifier else { return false }
        return exists(identifier: identifier)
    }
}

// MARK: - Errors

enum KeychainError: LocalizedError {
    case encodingFailed
    case saveFailed(OSStatus)
    case deleteFailed(OSStatus)
    case noIdentifier
    
    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "Failed to encode API key"
        case .saveFailed(let status):
            return "Failed to save to Keychain (error \(status))"
        case .deleteFailed(let status):
            return "Failed to delete from Keychain (error \(status))"
        case .noIdentifier:
            return "Provider does not support API key storage"
        }
    }
}
