import Foundation
import Security
import AdbCrypto

public struct PairingChallenge {
    public let serviceName: String
    public let password: String
    public var qrPayload: String { "WIFI:T:ADB;S:\(serviceName);P:\(password);;" }
    public init() throws {
        var bytes=[UInt8](repeating:0,count:32)
        guard SecRandomCopyBytes(kSecRandomDefault,bytes.count,&bytes) == errSecSuccess else { throw ScrcpyError.message("Cannot generate pairing secret") }
        // Hex avoids the QR Wi-Fi escaping characters and modulo bias.
        serviceName="studio-"+bytes.prefix(8).map { String(format:"%02x",$0) }.joined()
        password=bytes.suffix(16).map { String(format:"%02x",$0) }.joined()
    }
}

public final class AdbPairingClient {
    private let transport: SocketTransport
    private let identity: AdbIdentity
    private let clientName: String
    public init(host: String, port: Int, identity: AdbIdentity, clientName: String) throws {
        var profile=Profile(); profile.host=host; profile.port=port; try profile.validate()
        _ = try identity.adbPublicKey(name:clientName)
        self.transport=try SocketTransport(host:host,port:port); self.identity=identity; self.clientName=clientName
    }
    public func cancel() { transport.close() }
    public func pair(password: String) throws -> String {
        guard !password.isEmpty, password.utf8.count <= 128, !password.contains("\0") else { throw ScrcpyError.message("Invalid pairing secret") }
        let timeout=DispatchWorkItem { [weak self] in self?.cancel() }
        DispatchQueue.global().asyncAfter(deadline:.now()+45,execute:timeout)
        defer { timeout.cancel(); transport.close() }
        try transport.connect(); try transport.startTLS(identity:identity)
        var secret=Data(password.utf8); secret += try transport.exportedKey()
        defer { secret.resetBytes(in:0..<secret.count) }
        guard let pairing=secret.withUnsafeBytes({ sc_pair_create($0.bindMemory(to:UInt8.self).baseAddress,secret.count) }) else { throw ScrcpyError.message("Cannot initialize ADB pairing") }
        defer { sc_pair_free(pairing) }
        var message=[UInt8](repeating:0,count:128)
        let count=sc_pair_message(pairing,&message,message.count)
        guard count > 0 else { throw ScrcpyError.message("Cannot create pairing message") }
        try writePacket(type:0,bytes:Data(message.prefix(Int(count))))
        let peer=try readPacket(type:0,limit:128)
        guard peer.withUnsafeBytes({ sc_pair_process(pairing,$0.bindMemory(to:UInt8.self).baseAddress,peer.count) }) == 1 else { throw ScrcpyError.message("Pairing code was rejected") }
        var info=Data([0]); info += try identity.adbPublicKey(name:clientName)
        guard info.count <= 8192 else { throw ScrcpyError.message("Pairing name is too long") }; info.append(Data(repeating:0,count:8192-info.count))
        var encrypted=[UInt8](repeating:0,count:8208)
        let encryptedCount=info.withUnsafeBytes { sc_pair_encrypt(pairing,$0.bindMemory(to:UInt8.self).baseAddress,info.count,&encrypted,encrypted.count) }
        guard encryptedCount == 8208 else { throw ScrcpyError.message("Cannot encrypt pairing identity") }
        try writePacket(type:1,bytes:Data(encrypted))
        let response=try readPacket(type:1,limit:8208)
        var decrypted=[UInt8](repeating:0,count:8208)
        let length=response.withUnsafeBytes { sc_pair_decrypt(pairing,$0.bindMemory(to:UInt8.self).baseAddress,response.count,&decrypted,decrypted.count) }
        guard length == 8192, decrypted[0] == 1 else { throw ScrcpyError.message("Pairing failed; check the code and keep the Android pairing window open") }
        let guid=String(decoding:decrypted.dropFirst().prefix(8191).prefix(while:{$0 != 0}),as:UTF8.self)
        guard !guid.isEmpty, guid.utf8.count <= 128 else { throw ScrcpyError.message("Invalid paired-device identity") }
        return guid
    }
    private func writePacket(type: UInt8, bytes: Data) throws { var header=Data([1,type]); header.appendBE(UInt32(bytes.count)); try transport.write(header+bytes) }
    private func readPacket(type: UInt8, limit: Int) throws -> Data {
        let header=try transport.read(6), size=Int(header.uint32BE(2))
        guard header[0] == 1, header[1] == type, size > 0, size <= limit else { throw ScrcpyError.message("Invalid pairing packet") }
        return try transport.read(size)
    }
}
