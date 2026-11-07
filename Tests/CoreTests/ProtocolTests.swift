import XCTest
@testable import ScrcpyCore
import Security

final class ProtocolTests: XCTestCase {
    func testAdbPacketRoundTripAndCorruption() throws {
        let packet = AdbPacket("WRTE", 1, 2, Data([1,2,255])), bytes = packet.encoded()
        let decoded = try AdbPacket.decode(header: bytes.prefix(24), payload: bytes.suffix(3))
        XCTAssertEqual(decoded.arg1, 2); XCTAssertEqual(decoded.payload, Data([1,2,255]))
        XCTAssertThrowsError(try AdbPacket.decode(header: bytes.prefix(24), payload: Data([1,2,0])))
    }
    func testTouchWireFormat() {
        let bytes = Control.touch(action: 0, pointer: 42, x: 10, y: 20, width: 1080, height: 2340, pressure: 1)
        XCTAssertEqual(bytes.count, 32); XCTAssertEqual(bytes.uint64BE(2), 42); XCTAssertEqual(bytes.uint32BE(10), 10)
        XCTAssertEqual(bytes.uint16BE(18), 1080); XCTAssertEqual(bytes.uint16BE(22), 65535)
    }
    func testChordModifierReleaseOrder() {
        let bytes = Control.chord(36, meta: 0x33053)
        XCTAssertEqual(bytes.count, 14 * 10)
        XCTAssertEqual(bytes.uint32BE(2), 113)
        XCTAssertEqual(bytes.uint32BE(14 * 6 + 2), 117)
        XCTAssertEqual(bytes[14 * 9 + 1], 1)
    }
    func testClipboardByteLimit() throws {
        let text = String(repeating: "你", count: 21845)
        XCTAssertEqual(try Control.paste(text).uint32BE(10), 65535)
        XCTAssertThrowsError(try Control.paste(text + "你"))
    }
    func testAnnexBAndLengthPrefix() {
        let units = AnnexB.units(Data([0,0,0,1,0x67,1,2,0,0,1,0x68,3]))
        XCTAssertEqual(units, [Data([0x67,1,2]), Data([0x68,3])]); XCTAssertEqual(AnnexB.lengthPrefixed(units).uint32BE(), 3)
    }
    func testKeyMapping() {
        XCTAssertEqual(KeyStroke.character("A")?.code, 29); XCTAssertEqual(KeyStroke.character("A")?.meta, 0x41)
        XCTAssertEqual(KeyStroke.character("@")?.code, 9); XCTAssertEqual(KeyStroke.character("@")?.meta, 0x41)
        XCTAssertEqual(KeyStroke.character("0")?.code, 7); XCTAssertNil(KeyStroke.character("你"))
    }
    func testProfileValidation() throws {
        var profile = Profile(); XCTAssertThrowsError(try profile.validate()); profile.host = "device.example"; try profile.validate()
        profile.port = 65536; XCTAssertThrowsError(try profile.validate())
    }
    func testOldProfileDefaults() throws {
        let value = try JSONDecoder().decode(Profile.self, from: Data(#"{"host":"device.example","port":5555}"#.utf8))
        XCTAssertFalse(value.forwardMic); XCTAssertTrue(value.forwardAudio); XCTAssertTrue(value.showNavigation)
    }
    func testAndroidPublicKeyAndSignature() throws {
        let identity = try AdbIdentity(persistent: false), publicBytes = try identity.adbPublicKey()
        let base64 = String(decoding: publicBytes, as: UTF8.self).split(separator: " ")[0]
        let structure = try XCTUnwrap(Data(base64Encoded: String(base64)))
        XCTAssertEqual(structure.count, 524); XCTAssertEqual(structure.uint32LE(), 64); XCTAssertEqual(structure.uint32LE(520), 65537)
        XCTAssertEqual(structure.uint32LE(4) &* structure.uint32LE(8), UInt32.max)
        let digest = Data(repeating: 0x42, count: 20), signature = try identity.sign(digest)
        var error: Unmanaged<CFError>?
        XCTAssertTrue(SecKeyVerifySignature(identity.publicKey, .rsaSignatureDigestPKCS1v15SHA1, digest as CFData, signature as CFData, &error))
        XCTAssertThrowsError(try identity.sign(Data(repeating: 0, count: 21)))
    }
}
