import Foundation
import Security

public final class AdbIdentity {
    private let privateKey: SecKey
    public init(persistent: Bool = true) throws {
        let tag = Data("cn.oh-my-term.scrcpy.adb-rsa".utf8)
        if persistent {
            var found: CFTypeRef?
            let status = SecItemCopyMatching([kSecClass: kSecClassKey, kSecAttrApplicationTag: tag, kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecReturnRef: true] as CFDictionary, &found)
            if status == errSecSuccess, let found { privateKey = (found as! SecKey); return }
            guard status == errSecItemNotFound else { throw ScrcpyError.message("Cannot read ADB identity from Keychain: \(status)") }
        }
        var error: Unmanaged<CFError>?
        var attributes: [CFString: Any] = [kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeySizeInBits: 2048]
        if persistent { attributes[kSecPrivateKeyAttrs] = [kSecAttrIsPermanent: true, kSecAttrApplicationTag: tag, kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly] }
        guard let key = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else { throw (error?.takeRetainedValue() as Error?) ?? ScrcpyError.message("Cannot create ADB identity") }
        privateKey = key
    }
    public func sign(_ digest: Data) throws -> Data {
        guard digest.count == 20 else { throw ScrcpyError.message("Invalid ADB authentication challenge") }
        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(privateKey, .rsaSignatureDigestPKCS1v15SHA1, digest as CFData, &error) else { throw error!.takeRetainedValue() }
        return signature as Data
    }
    public var publicKey: SecKey { SecKeyCopyPublicKey(privateKey)! }
    func privateKeyDER() throws -> Data {
        var error: Unmanaged<CFError>?
        guard let bytes = SecKeyCopyExternalRepresentation(privateKey,&error) else { throw (error?.takeRetainedValue() as Error?) ?? ScrcpyError.message("Cannot use ADB identity for TLS") }; return bytes as Data
    }
    public func adbPublicKey(name: String = "scrcpy-ios") throws -> Data {
        var error: Unmanaged<CFError>?
        guard let raw = SecKeyCopyExternalRepresentation(publicKey, &error) else { throw error!.takeRetainedValue() }
        let (modulus, exponent) = try Self.parseRSA(raw as Data)
        return try Self.androidPublicKey(modulus: modulus, exponent: exponent, name: name)
    }
    public static func parseRSA(_ der: Data) throws -> (Data, UInt32) {
        let bytes = [UInt8](der); var cursor = 0
        func item(_ tag: UInt8) throws -> Data {
            guard cursor + 2 <= bytes.count, bytes[cursor] == tag else { throw ScrcpyError.message("Invalid RSA public key") }; cursor += 1
            var size = Int(bytes[cursor]); cursor += 1
            if size & 128 != 0 {
                let count = size & 127; guard count > 0 && count <= 4 && cursor + count <= bytes.count else { throw ScrcpyError.message("Invalid DER length") }
                size = 0; for _ in 0..<count { size = size * 256 + Int(bytes[cursor]); cursor += 1 }
            }
            guard size >= 0 && cursor + size <= bytes.count else { throw ScrcpyError.message("Invalid DER payload") }
            let result = Data(bytes[cursor..<cursor + size]); cursor += size; return result
        }
        let sequence = try item(0x30)
        let inner = [UInt8](sequence); cursor = 0
        // Parse the sequence with a fresh reader, preserving strict length checks.
        func integer() throws -> Data {
            guard cursor + 2 <= inner.count, inner[cursor] == 2 else { throw ScrcpyError.message("Invalid RSA integer") }; cursor += 1
            var size = Int(inner[cursor]); cursor += 1
            if size & 128 != 0 { let count = size & 127; guard count > 0 && count <= 4 && cursor + count <= inner.count else { throw ScrcpyError.message("Invalid RSA length") }; size = 0; for _ in 0..<count { size = size * 256 + Int(inner[cursor]); cursor += 1 } }
            guard size > 0 && cursor + size <= inner.count else { throw ScrcpyError.message("Truncated RSA integer") }
            var result = Data(inner[cursor..<cursor + size]); cursor += size; while result.count > 1 && result.first == 0 { result.removeFirst() }; return result
        }
        let modulus = try integer(), e = try integer(); guard e.count <= 4, modulus.count == 256 else { throw ScrcpyError.message("ADB requires RSA 2048") }
        return (modulus, e.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) })
    }
    public static func androidPublicKey(modulus: Data, exponent: UInt32, name: String = "scrcpy-ios") throws -> Data {
        guard modulus.count == 256, modulus.last! & 1 == 1 else { throw ScrcpyError.message("Invalid RSA modulus") }
        let little = Data(modulus.reversed()), n = (0..<64).map { little.uint32LE($0 * 4) }
        var inverse: UInt32 = 1
        for _ in 0..<5 { inverse = inverse &* (2 &- n[0] &* inverse) }
        var rr = [UInt32](repeating: 0, count: 64); rr[0] = 1
        for _ in 0..<4096 {
            var carry: UInt32 = 0
            for i in 0..<64 { let next = rr[i] >> 31; rr[i] = (rr[i] << 1) | carry; carry = next }
            let greater = zip(rr.reversed(), n.reversed()).first(where: { $0 != $1 }).map { $0 > $1 } ?? true
            if carry != 0 || greater {
                var borrow: UInt64 = 0
                for i in 0..<64 { let sub = UInt64(n[i]) + borrow; let a = UInt64(rr[i]); rr[i] = UInt32(truncatingIfNeeded: a &- sub); borrow = a < sub ? 1 : 0 }
            }
        }
        var out = Data(); out.appendLE(64); out.appendLE(0 &- inverse); out += little; for value in rr { out.appendLE(value) }; out.appendLE(exponent)
        return Data((out.base64EncodedString() + " " + (try Self.deviceLabel(name)) + "\0").utf8)
    }
    public static func deviceLabel(_ name: String) throws -> String {
        let clean=name.replacingOccurrences(of:"\0",with:"").trimmingCharacters(in:.whitespacesAndNewlines)
        // Android's paired-device parser splits on Unicode whitespace too.
        let label=String(clean.map { $0.isWhitespace ? Character("_") : $0 })
        guard !label.isEmpty, label.utf8.count <= 120 else { throw ScrcpyError.message("Device name must contain 1–120 UTF-8 bytes") }
        return label
    }
}
