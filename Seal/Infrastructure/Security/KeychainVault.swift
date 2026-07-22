import Foundation
import Security

actor KeychainVault {
    private let service = "com.mjorb.seal.account"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    func save(_ secret: AccountSecret, for accountID: UUID) throws {
        let data = try encoder.encode(secret)
        let base = query(for: accountID)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String:
                kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let status = SecItemUpdate(base as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var insert = base
            attributes.forEach { insert[$0.key] = $0.value }
            let insertStatus = SecItemAdd(insert as CFDictionary, nil)
            guard insertStatus == errSecSuccess else {
                throw KeychainError(status: insertStatus)
            }
        } else if status != errSecSuccess {
            throw KeychainError(status: status)
        }
    }

    func load(accountID: UUID) throws -> AccountSecret? {
        var request = query(for: accountID)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw KeychainError(status: status)
        }
        return try decoder.decode(AccountSecret.self, from: data)
    }

    func delete(accountID: UUID) throws {
        let status = SecItemDelete(query(for: accountID) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError(status: status)
        }
    }

    func clearSigningMaterial(accountID: UUID) throws {
        guard var secret = try load(accountID: accountID) else { return }
        secret.certificateP12 = nil
        secret.certificateSerialNumber = nil
        secret.certificateMachineIdentifier = nil
        try save(secret, for: accountID)
    }

    func signingMaterialSummary(accountID: UUID) throws -> SigningMaterialSummary? {
        guard let secret = try load(accountID: accountID) else { return nil }
        return SigningMaterialSummary(
            accountIdentifier: secret.accountIdentifier,
            hasCertificateP12: secret.certificateP12 != nil,
            certificateSerialNumber: secret.certificateSerialNumber,
            certificateMachineIdentifier: secret.certificateMachineIdentifier
        )
    }

    private func query(for accountID: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountID.uuidString,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any
        ]
    }
}

struct KeychainError: Error, Equatable, Sendable {
    let status: OSStatus
}


struct SigningMaterialSummary: Equatable, Sendable {
    let accountIdentifier: String
    let hasCertificateP12: Bool
    let certificateSerialNumber: String?
    let certificateMachineIdentifier: String?
}
