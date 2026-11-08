import Foundation
import AdbCrypto

/// A memory BIO prevents SSL_read from blocking writes and keeps every access
/// to BoringSSL on the transport's lock, including ordered outgoing records.
final class AdbTLS {
    let context: OpaquePointer
    init(identity: AdbIdentity) throws {
        var bytes = try identity.privateKeyDER()
        defer { bytes.resetBytes(in:0..<bytes.count) }
        guard let context = bytes.withUnsafeBytes({ sc_tls_create($0.bindMemory(to:UInt8.self).baseAddress,bytes.count) }) else { throw Self.error() }
        self.context = context
    }
    static func error() -> ScrcpyError { var text = [CChar](repeating:0,count:300); sc_tls_error(&text,text.count); return .message("ADB TLS: " + String(cString:text)) }
    func feed(_ bytes: Data) throws { guard bytes.withUnsafeBytes({ sc_tls_feed(context,$0.bindMemory(to:UInt8.self).baseAddress,bytes.count) }) == 1 else { throw Self.error() } }
    func output() -> Data {
        var out = Data(), buffer = [UInt8](repeating:0,count:16384)
        while true { let n = sc_tls_drain(context,&buffer,buffer.count); if n <= 0 { return out }; out.append(contentsOf:buffer.prefix(Int(n))) }
    }
    func exportedKey() throws -> Data { var bytes = [UInt8](repeating:0,count:64); guard sc_tls_export(context,&bytes) == 1 else { throw Self.error() }; return Data(bytes) }
    deinit { sc_tls_free(context) }
}
