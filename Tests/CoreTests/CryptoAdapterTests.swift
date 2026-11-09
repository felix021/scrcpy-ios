import XCTest
@testable import ScrcpyCore
import AdbCrypto

final class CryptoAdapterTests: XCTestCase {
    func testTLSRejectsInvalidIdentityAndStartsWithoutNetworkIO() throws {
        XCTAssertNil(sc_tls_create(nil, 0))
        let malformed = Data([0x30, 0])
        XCTAssertNil(malformed.withUnsafeBytes { sc_tls_create($0.bindMemory(to: UInt8.self).baseAddress, malformed.count) })
        let der = try AdbIdentity(persistent: false).privateKeyDER()
        let tls = try XCTUnwrap(der.withUnsafeBytes { sc_tls_create($0.bindMemory(to: UInt8.self).baseAddress, der.count) })
        defer { sc_tls_free(tls) }
        XCTAssertEqual(sc_tls_handshake(tls), 0)
        var hello = [UInt8](repeating: 0, count: 32768)
        let size = sc_tls_drain(tls, &hello, hello.count)
        XCTAssertGreaterThan(size, 5)
        XCTAssertEqual(hello[0], 22) // A TLS handshake record, held for Swift to send.
        XCTAssertEqual(sc_tls_drain(tls, &hello, hello.count), 0)
        XCTAssertEqual(sc_tls_feed(tls, nil, 1), 0)
    }

    func testPairingRejectsInvalidPeerAndCannotEncryptBeforeAuthentication() throws {
        XCTAssertNil(sc_pair_create(nil, 0))
        let secret = Data("pairing-test-secret".utf8)
        let pair = try XCTUnwrap(secret.withUnsafeBytes { sc_pair_create($0.bindMemory(to: UInt8.self).baseAddress, secret.count) })
        defer { sc_pair_free(pair) }
        var message = [UInt8](repeating: 0, count: 128)
        XCTAssertGreaterThan(sc_pair_message(pair, &message, message.count), 0)
        XCTAssertEqual(sc_pair_message(pair, &message, 1), -1)
        var invalidPeer: [UInt8] = [1, 2, 3]
        XCTAssertEqual(sc_pair_encrypt(pair, &invalidPeer, invalidPeer.count, &message, message.count), -1)
        XCTAssertEqual(sc_pair_process(pair, &invalidPeer, invalidPeer.count), 0)
        XCTAssertEqual(sc_pair_process(pair, &invalidPeer, invalidPeer.count), 0)
        XCTAssertEqual(sc_pair_decrypt(pair, &invalidPeer, invalidPeer.count, &message, message.count), -1)
    }
}
