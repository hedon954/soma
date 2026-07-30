import CryptoKit
import Foundation
import Security

enum DataBackupCrypto {
    static let defaultIterations = 120_000
    static let keyByteCount = 32
    static let saltByteCount = 16

    static func randomSalt() throws -> Data {
        var bytes = [UInt8](repeating: 0, count: saltByteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw DataArchiveError.invalidBackup
        }
        return Data(bytes)
    }

    static func deriveKeyData(
        password: String,
        salt: Data,
        iterations: Int = defaultIterations,
        outputByteCount: Int = keyByteCount
    ) throws -> Data {
        guard password.count >= 8 else { throw DataArchiveError.invalidPassword }
        guard salt.count >= saltByteCount,
              iterations > 0,
              iterations <= 1_000_000,
              outputByteCount > 0,
              outputByteCount <= 64
        else {
            throw DataArchiveError.invalidBackup
        }

        let passwordKey = SymmetricKey(data: Data(password.utf8))
        let digestLength = SHA256.byteCount
        let blockCount = Int(ceil(Double(outputByteCount) / Double(digestLength)))
        var derived = Data()

        for blockIndex in 1 ... blockCount {
            var blockData = salt
            var index = UInt32(blockIndex).bigEndian
            withUnsafeBytes(of: &index) { blockData.append(contentsOf: $0) }

            var previous = Data(HMAC<SHA256>.authenticationCode(
                for: blockData,
                using: passwordKey
            ))
            var accumulated = previous
            if iterations > 1 {
                for _ in 2 ... iterations {
                    previous = Data(HMAC<SHA256>.authenticationCode(
                        for: previous,
                        using: passwordKey
                    ))
                    accumulated.xor(with: previous)
                }
            }
            derived.append(accumulated)
        }
        return derived.prefix(outputByteCount)
    }

    static func seal(_ plaintext: Data, keyData: Data) throws -> Data {
        guard keyData.count == keyByteCount else {
            throw DataArchiveError.invalidBackup
        }
        let sealed = try AES.GCM.seal(
            plaintext,
            using: SymmetricKey(data: keyData)
        )
        guard let combined = sealed.combined else {
            throw DataArchiveError.invalidBackup
        }
        return combined
    }

    static func open(_ ciphertext: Data, keyData: Data) throws -> Data {
        guard keyData.count == keyByteCount else {
            throw DataArchiveError.invalidPasswordOrCorruptBackup
        }
        do {
            let box = try AES.GCM.SealedBox(combined: ciphertext)
            return try AES.GCM.open(box, using: SymmetricKey(data: keyData))
        } catch {
            throw DataArchiveError.invalidPasswordOrCorruptBackup
        }
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

private extension Data {
    mutating func xor(with other: Data) {
        withUnsafeMutableBytes { target in
            other.withUnsafeBytes { source in
                guard let targetBase = target.bindMemory(to: UInt8.self).baseAddress,
                      let sourceBase = source.bindMemory(to: UInt8.self).baseAddress
                else {
                    return
                }
                for index in 0 ..< Swift.min(target.count, source.count) {
                    targetBase[index] ^= sourceBase[index]
                }
            }
        }
    }
}
