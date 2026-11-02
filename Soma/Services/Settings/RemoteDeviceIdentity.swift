import CryptoKit
import DeviceCheck
import Foundation
import Security

struct RemoteRegistrationAttestation: Sendable {
    var object: String
    var keyID: String
}

final class RemoteDeviceIdentity: @unchecked Sendable {
    static let shared = RemoteDeviceIdentity()

    private enum Account {
        static let deviceID = "agent.remote.deviceID"
        static let accessToken = "agent.remote.accessToken"
        static let rotationToken = "agent.remote.rotationToken"
        static let tokenExpiry = "agent.remote.tokenExpiry"
        static let appAttestKeyID = "agent.remote.appAttestKeyID"
    }

    private static let signingKeyTag = Data(
        "top.hedon.soma.remote-signing-key".utf8
    )
    private let lock = NSLock()
    private let usesEphemeralStorage: Bool
    private var ephemeralDeviceID: UUID?
    private var ephemeralAccessToken: String?
    private var ephemeralRotationToken: String?
    private var ephemeralAccessTokenExpiry: Date?
    private var ephemeralSigningKey: SecKey?

    init(usesEphemeralStorage: Bool = false) {
        self.usesEphemeralStorage = usesEphemeralStorage
    }

    var deviceID: UUID {
        lock.withLock {
            if usesEphemeralStorage {
                if let ephemeralDeviceID {
                    return ephemeralDeviceID
                }
                let value = UUID()
                ephemeralDeviceID = value
                return value
            }
            if let rawValue = KeychainStore.read(Account.deviceID),
               let value = UUID(uuidString: rawValue)
            {
                return value
            }
            let value = UUID()
            KeychainStore.save(value.uuidString.lowercased(), for: Account.deviceID)
            return value
        }
    }

    var accessToken: String? {
        if usesEphemeralStorage {
            return lock.withLock { ephemeralAccessToken }
        }
        return KeychainStore.read(Account.accessToken)
    }

    var rotationToken: String? {
        if usesEphemeralStorage {
            return lock.withLock { ephemeralRotationToken }
        }
        return KeychainStore.read(Account.rotationToken)
    }

    var accessTokenExpiry: Date? {
        if usesEphemeralStorage {
            return lock.withLock { ephemeralAccessTokenExpiry }
        }
        return KeychainStore.read(Account.tokenExpiry)
            .flatMap(TimeInterval.init)
            .map(Date.init(timeIntervalSince1970:))
    }

    func storeTokens(
        accessToken: String,
        rotationToken: String? = nil,
        expiresAt: Date
    ) {
        if usesEphemeralStorage {
            lock.withLock {
                ephemeralAccessToken = accessToken
                if let rotationToken {
                    ephemeralRotationToken = rotationToken
                }
                ephemeralAccessTokenExpiry = expiresAt
            }
            return
        }
        KeychainStore.save(accessToken, for: Account.accessToken)
        if let rotationToken {
            KeychainStore.save(rotationToken, for: Account.rotationToken)
        }
        KeychainStore.save(
            String(expiresAt.timeIntervalSince1970),
            for: Account.tokenExpiry
        )
    }

    func publicKeyPEM() throws -> String {
        let key = try signingPrivateKey()
        guard let publicKey = SecKeyCopyPublicKey(key),
              let rawValue = SecKeyCopyExternalRepresentation(
                  publicKey,
                  nil
              ) as Data?
        else {
            throw RemoteAgentError.identityUnavailable
        }
        // CryptoKit/Security exports an uncompressed ANSI X9.63 point. Wrap it
        // in the standard P-256 SubjectPublicKeyInfo envelope expected by the
        // server and common OpenSSL implementations.
        let prefix = Data([
            0x30, 0x59, 0x30, 0x13, 0x06, 0x07, 0x2A, 0x86,
            0x48, 0xCE, 0x3D, 0x02, 0x01, 0x06, 0x08, 0x2A,
            0x86, 0x48, 0xCE, 0x3D, 0x03, 0x01, 0x07, 0x03,
            0x42, 0x00
        ])
        let encoded = (prefix + rawValue).base64EncodedString()
        let lines = stride(
            from: Int.zero,
            to: encoded.utf8.count,
            by: 64
        ).map { offset in
            let start = encoded.index(encoded.startIndex, offsetBy: offset)
            let end = encoded.index(
                start,
                offsetBy: min(
                    64,
                    encoded.distance(from: start, to: encoded.endIndex)
                )
            )
            return String(encoded[start ..< end])
        }
        return (["-----BEGIN PUBLIC KEY-----"] + lines + [
            "-----END PUBLIC KEY-----"
        ]).joined(separator: "\n")
    }

    func sign(_ value: Data) throws -> String {
        let key = try signingPrivateKey()
        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(
            key,
            .ecdsaSignatureMessageX962SHA256,
            value as CFData,
            &error
        ) as Data?
        else {
            throw error?.takeRetainedValue() ?? RemoteAgentError.identityUnavailable
        }
        return signature.base64EncodedString()
    }

    func appAttestation(
        challenge: String
    ) async throws -> RemoteRegistrationAttestation? {
        if usesEphemeralStorage {
            return nil
        }
        let service = DCAppAttestService.shared
        guard service.isSupported else { return nil }
        let keyID: String
        if let existing = KeychainStore.read(Account.appAttestKeyID) {
            keyID = existing
        } else {
            keyID = try await service.generateKey()
            KeychainStore.save(keyID, for: Account.appAttestKeyID)
        }
        let clientDataHash = Data(
            SHA256.hash(data: Data(challenge.utf8))
        )
        let object = try await service.attestKey(
            keyID,
            clientDataHash: clientDataHash
        )
        return RemoteRegistrationAttestation(
            object: object.base64EncodedString(),
            keyID: keyID
        )
    }

    func clearCredentials() {
        if usesEphemeralStorage {
            lock.withLock {
                ephemeralDeviceID = nil
                ephemeralAccessToken = nil
                ephemeralRotationToken = nil
                ephemeralAccessTokenExpiry = nil
                ephemeralSigningKey = nil
            }
            return
        }
        [
            Account.deviceID,
            Account.accessToken,
            Account.rotationToken,
            Account.tokenExpiry,
            Account.appAttestKeyID
        ].forEach(KeychainStore.delete)
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: Self.signingKeyTag,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom
        ]
        SecItemDelete(query as CFDictionary)
    }

    func clearTokens() {
        if usesEphemeralStorage {
            lock.withLock {
                ephemeralAccessToken = nil
                ephemeralRotationToken = nil
                ephemeralAccessTokenExpiry = nil
            }
            return
        }
        [
            Account.accessToken,
            Account.rotationToken,
            Account.tokenExpiry
        ].forEach(KeychainStore.delete)
    }

    private func signingPrivateKey() throws -> SecKey {
        if usesEphemeralStorage {
            return try lock.withLock {
                if let ephemeralSigningKey {
                    return ephemeralSigningKey
                }
                var error: Unmanaged<CFError>?
                guard let key = SecKeyCreateRandomKey(
                    [
                        kSecAttrKeyType as String:
                            kSecAttrKeyTypeECSECPrimeRandom,
                        kSecAttrKeySizeInBits as String: 256
                    ] as CFDictionary,
                    &error
                ) else {
                    throw error?.takeRetainedValue()
                        ?? RemoteAgentError.identityUnavailable
                }
                ephemeralSigningKey = key
                return key
            }
        }
        if let existing = existingSigningKey() {
            return existing
        }
        var attributes = baseSigningAttributes
        attributes[kSecAttrTokenID as String] = kSecAttrTokenIDSecureEnclave
        var error: Unmanaged<CFError>?
        if let key = SecKeyCreateRandomKey(attributes as CFDictionary, &error) {
            return key
        }
        // Secure Enclave is unavailable in Simulator and on a small set of
        // devices. The fallback is still non-exportable through this API and
        // remains ThisDeviceOnly in Keychain.
        attributes.removeValue(forKey: kSecAttrTokenID as String)
        error = nil
        guard let key = SecKeyCreateRandomKey(
            attributes as CFDictionary,
            &error
        ) else {
            throw error?.takeRetainedValue() ?? RemoteAgentError.identityUnavailable
        }
        return key
    }

    private var baseSigningAttributes: [String: Any] {
        [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: Self.signingKeyTag,
                kSecAttrAccessible as String:
                    kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            ]
        ]
    }

    private func existingSigningKey() -> SecKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: Self.signingKeyTag,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecReturnRef as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(
                  query as CFDictionary,
                  &result
              ) == errSecSuccess,
              let result,
              CFGetTypeID(result) == SecKeyGetTypeID()
        else {
            return nil
        }
        // swiftlint:disable:next force_cast
        return (result as! SecKey)
    }
}

private extension NSLock {
    func withLock<T>(_ operation: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try operation()
    }
}
