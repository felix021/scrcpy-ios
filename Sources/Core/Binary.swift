import Foundation

public enum ScrcpyError: Error, LocalizedError {
    case message(String)
    public var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

extension Data {
    public func uint16BE(_ offset: Int = 0) -> UInt16 { UInt16(self[startIndex + offset]) << 8 | UInt16(self[startIndex + offset + 1]) }
    public func uint32LE(_ offset: Int = 0) -> UInt32 { (0..<4).reduce(0) { $0 | UInt32(self[startIndex + offset + $1]) << (8 * $1) } }
    public func uint32BE(_ offset: Int = 0) -> UInt32 { (0..<4).reduce(0) { $0 << 8 | UInt32(self[startIndex + offset + $1]) } }
    public func uint64BE(_ offset: Int = 0) -> UInt64 { (0..<8).reduce(0) { $0 << 8 | UInt64(self[startIndex + offset + $1]) } }
    public mutating func appendLE(_ value: UInt32) { for i in 0..<4 { append(UInt8(truncatingIfNeeded: value >> (i * 8))) } }
    public mutating func appendBE(_ value: UInt32) { for i in (0..<4).reversed() { append(UInt8(truncatingIfNeeded: value >> (i * 8))) } }
    public mutating func appendBE(_ value: UInt16) { append(UInt8(truncatingIfNeeded: value >> 8)); append(UInt8(truncatingIfNeeded: value)) }
    public mutating func appendBE(_ value: UInt64) { for i in (0..<8).reversed() { append(UInt8(truncatingIfNeeded: value >> (i * 8))) } }
}

extension NSLock {
    func withValue<T>(_ action: () throws -> T) rethrows -> T { lock(); defer { unlock() }; return try action() }
}

public struct Profile: Codable, Identifiable, Equatable {
    public var id: UUID = UUID()
    public var name = ""
    public var host = ""
    public var port = 5555
    public var maxSize = 1600
    public var bitrate = 6
    public var fps = 60
    public var codec = "h264"
    public var showNavigation = true
    public var viewOnly = false
    public var syncRotation = true
    public var forwardAudio = true
    public var forwardMic = false
    public var stayAwake = true
    public init() {}
    public init(from decoder: Decoder) throws {
        self.init(); let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(UUID.self, forKey: .id) ?? id
        name = try values.decodeIfPresent(String.self, forKey: .name) ?? name
        host = try values.decodeIfPresent(String.self, forKey: .host) ?? host
        port = try values.decodeIfPresent(Int.self, forKey: .port) ?? port
        maxSize = try values.decodeIfPresent(Int.self, forKey: .maxSize) ?? maxSize
        bitrate = try values.decodeIfPresent(Int.self, forKey: .bitrate) ?? bitrate
        fps = try values.decodeIfPresent(Int.self, forKey: .fps) ?? fps
        codec = try values.decodeIfPresent(String.self, forKey: .codec) ?? codec
        showNavigation = try values.decodeIfPresent(Bool.self, forKey: .showNavigation) ?? showNavigation
        viewOnly = try values.decodeIfPresent(Bool.self, forKey: .viewOnly) ?? viewOnly
        syncRotation = try values.decodeIfPresent(Bool.self, forKey: .syncRotation) ?? syncRotation
        forwardAudio = try values.decodeIfPresent(Bool.self, forKey: .forwardAudio) ?? forwardAudio
        forwardMic = try values.decodeIfPresent(Bool.self, forKey: .forwardMic) ?? forwardMic
        stayAwake = try values.decodeIfPresent(Bool.self, forKey: .stayAwake) ?? stayAwake
    }
    public func validate() throws {
        guard !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !host.contains("://"), !host.contains(where: { $0.isWhitespace || $0 == "/" }), (1...65535).contains(port) else { throw ScrcpyError.message("Invalid host or ADB port") }
        guard (maxSize == 0 || (256...8192).contains(maxSize)), (1...100).contains(bitrate), (1...120).contains(fps), ["h264", "h265"].contains(codec) else { throw ScrcpyError.message("Invalid video settings") }
    }
}

public enum Control {
    public static func key(action: UInt8, code: UInt32, meta: UInt32 = 0) -> Data {
        var result = Data([0, action]); result.appendBE(code); result.appendBE(UInt32(0)); result.appendBE(meta); return result
    }
    public static func chord(_ code: UInt32, meta: UInt32 = 0) -> Data {
        let codes: [UInt32] = [113, 57, 59, 117], masks: [UInt32] = [0x3000, 0x12, 0x41, 0x30000]
        var out = Data(), active = meta & ~UInt32(0x33053)
        for (keyCode, mask) in zip(codes, masks) where meta & mask != 0 { active |= mask; out += key(action: 0, code: keyCode, meta: active) }
        out += key(action: 0, code: code, meta: meta); out += key(action: 1, code: code, meta: meta)
        for i in codes.indices.reversed() where meta & masks[i] != 0 { active &= ~masks[i]; out += key(action: 1, code: codes[i], meta: active) }
        return out
    }
    public static func paste(_ text: String) throws -> Data {
        let bytes = Data(text.utf8); guard bytes.count <= 65536 else { throw ScrcpyError.message("Text exceeds 64 KiB") }
        var out = Data([9]); out.appendBE(UInt64(0)); out.append(1); out.appendBE(UInt32(bytes.count)); out += bytes; return out
    }
    public static func touch(action: UInt8, pointer: UInt64, x: Int, y: Int, width: Int, height: Int, pressure: Double) -> Data {
        var out = Data([2, action]); out.appendBE(pointer); out.appendBE(UInt32(clamping: x)); out.appendBE(UInt32(clamping: y)); out.appendBE(UInt16(clamping: width)); out.appendBE(UInt16(clamping: height)); out.appendBE(UInt16((min(1, max(0, pressure)) * 65535).rounded())); out.appendBE(UInt32(0)); out.appendBE(UInt32(0)); return out
    }
}

public struct VideoFrame {
    public let bytes: Data
    public let pts: UInt64
    public let config: Bool
    public let keyframe: Bool
}

public enum AnnexB {
    public static func units(_ data: Data) -> [Data] {
        let bytes = [UInt8](data); var starts: [(Int, Int)] = []; var index = 0
        while index + 2 < bytes.count {
            if bytes[index] == 0 && bytes[index + 1] == 0 {
                if bytes[index + 2] == 1 { starts.append((index, index + 3)); index += 3; continue }
                if index + 3 < bytes.count && bytes[index + 2] == 0 && bytes[index + 3] == 1 { starts.append((index, index + 4)); index += 4; continue }
            }
            index += 1
        }
        return starts.enumerated().compactMap { i, start in
            let end = i + 1 < starts.count ? starts[i + 1].0 : bytes.count
            return end > start.1 ? Data(bytes[start.1..<end]) : nil
        }
    }
    public static func lengthPrefixed(_ units: [Data]) -> Data {
        var result = Data(); for unit in units { result.appendBE(UInt32(unit.count)); result += unit }; return result
    }
}

public struct KeyStroke: Equatable {
    public let code: UInt32
    public let meta: UInt32
    public static func character(_ character: Character) -> KeyStroke? {
        let text = String(character), lower = text.lowercased()
        if let scalar = lower.unicodeScalars.first, lower.utf8.count == 1, (97...122).contains(scalar.value) { return KeyStroke(code: scalar.value - 97 + 29, meta: text != lower ? 0x41 : 0) }
        if let value = Int(text), (0...9).contains(value) { return KeyStroke(code: UInt32(7 + value), meta: 0) }
        let plain = [",":55, ".":56, "`":68, "-":69, "=":70, "[":71, "]":72, "\\":73, ";":74, "'":75, "/":76, " ":62]
        if let code = plain[text] { return KeyStroke(code: UInt32(code), meta: 0) }
        let shifted: [String: UInt32] = ["!":8,"@":9,"#":10,"$":11,"%":12,"^":13,"&":14,"*":15,"(":16,")":7,"~":68,"_":69,"+":70,"{":71,"}":72,"|":73,":":74,"\"":75,"?":76,"<":55,">":56]
        if let code = shifted[text] { return KeyStroke(code: code, meta: 0x41) }
        return nil
    }
}
