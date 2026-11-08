import Foundation
import Network
import AdbCrypto

public struct AdbPacket {
    public let command: UInt32
    public let arg0: UInt32
    public let arg1: UInt32
    public let payload: Data
    public static func code(_ name: String) -> UInt32 { Data(name.utf8).uint32LE() }
    public init(_ name: String, _ arg0: UInt32 = 0, _ arg1: UInt32 = 0, _ payload: Data = Data()) { command = Self.code(name); self.arg0 = arg0; self.arg1 = arg1; self.payload = payload }
    public func encoded() -> Data {
        var result = Data(); result.appendLE(command); result.appendLE(arg0); result.appendLE(arg1); result.appendLE(UInt32(payload.count)); result.appendLE(payload.reduce(UInt32(0)) { $0 &+ UInt32($1) }); result.appendLE(command ^ 0xffffffff); result += payload; return result
    }
    public static func decode(header: Data, payload: Data) throws -> AdbPacket {
        guard header.count == 24, header.uint32LE(20) == header.uint32LE(0) ^ 0xffffffff,
              header.uint32LE(12) == payload.count, payload.count <= 1024 * 1024 else { throw ScrcpyError.message("Invalid ADB packet") }
        let checksum = header.uint32LE(16)
        guard checksum == payload.reduce(UInt32(0), { $0 &+ UInt32($1) }) else { throw ScrcpyError.message("Invalid ADB checksum") }
        return AdbPacket(command: header.uint32LE(), arg0: header.uint32LE(4), arg1: header.uint32LE(8), payload: payload)
    }
    private init(command: UInt32, arg0: UInt32, arg1: UInt32, payload: Data) { self.command = command; self.arg0 = arg0; self.arg1 = arg1; self.payload = payload }
}

final class SocketTransport {
    private let tlsLock = NSLock(), rawWriteLock = NSLock()
    private var tls: AdbTLS?
    let connection: NWConnection
    private let queue = DispatchQueue(label: "scrcpy.socket")
    init(host: String, port: Int) throws {
        guard let port = NWEndpoint.Port(rawValue: UInt16(exactly: port) ?? 0), port.rawValue != 0 else { throw ScrcpyError.message("Invalid port") }
        let params = NWParameters.tcp; params.prohibitedInterfaceTypes = []
        connection = NWConnection(host: NWEndpoint.Host(host), port: port, using: params)
    }
    func connect() throws {
        let ready = DispatchSemaphore(value: 0); let lock = NSLock(); var result: Error?; var finished = false
        connection.stateUpdateHandler = { state in
            lock.lock(); defer { lock.unlock() }
            guard !finished else { return }
            switch state {
            case .ready: finished = true; ready.signal()
            case .failed(let e): result = e; finished = true; ready.signal()
            case .cancelled: result = ScrcpyError.message("Connection cancelled"); finished = true; ready.signal()
            default: break
            }
        }
        connection.start(queue: queue)
        guard ready.wait(timeout: .now() + 10) == .success else { connection.cancel(); throw ScrcpyError.message("ADB TCP connection timed out") }
        if let error = lock.withValue({ result }) { throw error }
    }
    private func rawRead(_ maximum: Int) throws -> Data {
        let done = DispatchSemaphore(value:0); var bytes: Data?; var failure: Error?
        connection.receive(minimumIncompleteLength:1,maximumLength:maximum) { data,_,_,error in bytes=data; failure=error; done.signal() }; done.wait()
        if let bytes, !bytes.isEmpty { return bytes }; throw failure ?? ScrcpyError.message("ADB connection closed")
    }
    func read(_ length: Int) throws -> Data {
        guard length >= 0 && length <= 1024 * 1024 else { throw ScrcpyError.message("Invalid read length") }
        var out = Data()
        while out.count < length {
            if let tls {
                var buffer = [UInt8](repeating:0,count:length-out.count)
                let count = try tlsLock.withValue { () -> Int in
                    let value = Int(sc_tls_read(tls.context,&buffer,buffer.count)); let pending=tls.output(); if !pending.isEmpty { try rawWrite(pending) }; return value
                }
                if count > 0 { out.append(contentsOf:buffer.prefix(count)) }
                else if count == -2 { let bytes=try rawRead(65536); try tlsLock.withValue { try tls.feed(bytes) } }
                else { throw AdbTLS.error() }
            } else { out += try rawRead(length-out.count) }

        }
        return out
    }
    private func rawWrite(_ data: Data) throws {
        try rawWriteLock.withValue { try sendRaw(data) }
    }
    private func sendRaw(_ data: Data) throws {
        let done = DispatchSemaphore(value: 0); var failure: Error?
        connection.send(content: data, completion: .contentProcessed { error in failure = error; done.signal() })
        guard done.wait(timeout: .now() + 15) == .success else { connection.cancel(); throw ScrcpyError.message("ADB write timed out") }
        if let failure { throw failure }
    }
    func write(_ data: Data) throws {
        guard let tls else { try rawWrite(data); return }
        try tlsLock.withValue {
            let written = data.withUnsafeBytes { sc_tls_write(tls.context,$0.bindMemory(to:UInt8.self).baseAddress,data.count) }
            guard written == data.count else { throw AdbTLS.error() }
            let pending = tls.output(); if !pending.isEmpty { try rawWrite(pending) }
        }
    }
    func startTLS(identity: AdbIdentity) throws {
        let session=try AdbTLS(identity:identity); tls=session
        while true {
            let status=try tlsLock.withValue { () -> Int32 in let result=sc_tls_handshake(session.context); let pending=session.output(); if !pending.isEmpty { try rawWrite(pending) }; return result }
            if status == 1 { return }; if status < 0 { throw AdbTLS.error() }
            let bytes=try rawRead(65536); try tlsLock.withValue { try session.feed(bytes) }
        }
    }
    func exportedKey() throws -> Data { try tlsLock.withValue { guard let tls else { throw ScrcpyError.message("No TLS session") }; return try tls.exportedKey() } }
    func close() { connection.cancel() }
}

public final class AdbConnection {
    private let transport: SocketTransport
    private let identity: AdbIdentity
    private let clientName: String
    private let lock = NSLock(), writeLock = NSLock()
    private var streams: [UInt32: AdbStream] = [:]
    private var nextID: UInt32 = 1
    private var closed = false
    public private(set) var maxData = 256 * 1024
    public var onClose: ((Error) -> Void)?
    public init(host: String, port: Int, identity: AdbIdentity, clientName: String = "scrcpy-ios") throws { self.clientName = clientName; transport = try SocketTransport(host: host, port: port); self.identity = identity }
    public func connect() throws {
        try transport.connect()
        let timeout = DispatchWorkItem { [weak self] in self?.close() }
        DispatchQueue.global().asyncAfter(deadline: .now() + 60, execute: timeout)
        defer { timeout.cancel() }
        try send(AdbPacket("CNXN", 0x01000000, 256 * 1024, Data("host::\0".utf8)))
        var signed = false, upgraded = false
        while true {
            let packet = try receive()
            if packet.command == AdbPacket.code("CNXN") {
                guard packet.arg1 >= 4096 else { throw ScrcpyError.message("Invalid ADB peer payload limit") }
                maxData = min(Int(packet.arg1), 1024 * 1024)
                Thread.detachNewThread { [self] in pump() }; return
            }
            if packet.command == AdbPacket.code("STLS") {
                guard !upgraded else { throw ScrcpyError.message("Repeated ADB TLS upgrade") }; upgraded=true
                try send(AdbPacket("STLS",0x01000000)); try transport.startTLS(identity:identity); continue
            }
            if packet.command == AdbPacket.code("AUTH"), packet.arg0 == 1 {
                if !signed { try send(AdbPacket("AUTH", 2, 0, identity.sign(packet.payload))); signed = true }
                else { try send(AdbPacket("AUTH", 3, 0, identity.adbPublicKey(name: clientName))) }
            } else { throw ScrcpyError.message("Unexpected ADB authentication response") }
        }
    }
    private func receive() throws -> AdbPacket {
        let header = try transport.read(24), size = header.uint32LE(12)
        guard size <= 1024 * 1024 else { throw ScrcpyError.message("Oversized ADB packet") }
        return try AdbPacket.decode(header: header, payload: transport.read(Int(size)))
    }
    fileprivate func send(_ packet: AdbPacket) throws { try writeLock.withValue { try transport.write(packet.encoded()) } }
    private func pump() {
        do {
            while !lock.withValue({ closed }) {
                let packet = try receive()
                if let stream = lock.withValue({ streams[packet.arg1] }) {
                    switch packet.command {
                    case AdbPacket.code("OKAY"): stream.ack(packet.arg0)
                    case AdbPacket.code("WRTE"): stream.enqueue(packet.payload)
                    case AdbPacket.code("CLSE"):
                        stream.peerClosed()
                        try? send(AdbPacket("CLSE", stream.id, packet.arg0))
                        _ = lock.withValue { streams.removeValue(forKey: stream.id) }
                    default: break
                    }
                } else if packet.command == AdbPacket.code("WRTE") { try send(AdbPacket("CLSE", packet.arg1, packet.arg0)) }
            }
        } catch { let notify = !lock.withValue { closed }; close(); if notify { onClose?(error) } }
    }
    public func open(_ destination: String, timeout: TimeInterval = 10) throws -> AdbStream {
        let stream: AdbStream = try lock.withValue {
            guard !closed else { throw ScrcpyError.message("Session closed") }
            let id = nextID; nextID &+= 1
            let stream = AdbStream(id: id, connection: self); streams[id] = stream; return stream
        }
        do { try send(AdbPacket("OPEN", stream.id, 0, Data((destination + "\0").utf8))); try stream.waitOpen(timeout); return stream }
        catch { stream.close(); throw error }
    }
    fileprivate func remove(_ id: UInt32) { _ = lock.withValue { streams.removeValue(forKey: id) } }
    public func close() {
        let all: [AdbStream] = lock.withValue { if closed { return [] }; closed = true; let values = Array(streams.values); streams.removeAll(); return values }
        transport.close(); all.forEach { $0.peerClosed() }
    }
    deinit { close() }
}

public final class AdbStream {
    fileprivate let id: UInt32
    private weak var connection: AdbConnection?
    private let condition = NSCondition(), writer = NSLock()
    private var remote: UInt32 = 0, ready = false, closed = false
    private var packets: [Data] = [], offset = 0
    fileprivate init(id: UInt32, connection: AdbConnection) { self.id = id; self.connection = connection }
    fileprivate func ack(_ remote: UInt32) { condition.lock(); self.remote = remote; ready = true; condition.broadcast(); condition.unlock() }
    fileprivate func enqueue(_ data: Data) { condition.lock(); if !closed { packets.append(data) }; condition.broadcast(); condition.unlock() }
    fileprivate func peerClosed() { condition.lock(); closed = true; condition.broadcast(); condition.unlock() }
    fileprivate func waitOpen(_ timeout: TimeInterval) throws {
        condition.lock(); defer { condition.unlock() }; let end = Date().addingTimeInterval(timeout)
        while remote == 0 && !closed { if !condition.wait(until: end) { throw ScrcpyError.message("ADB channel timed out") } }
        if remote == 0 { throw ScrcpyError.message("ADB channel unavailable") }
    }
    public func read(_ length: Int) throws -> Data {
        guard length >= 0 && length <= 16 * 1024 * 1024 else { throw ScrcpyError.message("Invalid stream read") }
        var out = Data()
        while out.count < length {
            condition.lock()
            while packets.isEmpty && !closed { condition.wait() }
            guard !packets.isEmpty else { condition.unlock(); throw ScrcpyError.message("ADB stream closed") }
            let first = packets[0], count = min(length - out.count, first.count - offset)
            out.append(first.subdata(in: offset..<offset + count)); offset += count
            let consumed = offset == first.count, peer = remote
            if consumed { packets.removeFirst(); offset = 0 }
            condition.unlock()
            if consumed { try? connection?.send(AdbPacket("OKAY", id, peer)) }
        }
        return out
    }
    public func readChunk() throws -> Data {
        condition.lock()
        while packets.isEmpty && !closed { condition.wait() }
        guard !packets.isEmpty else { condition.unlock(); throw ScrcpyError.message("ADB stream closed") }
        let first = packets.removeFirst(); let packet = first.subdata(in: offset..<first.count)
        offset = 0; let peer = remote; condition.unlock()
        try? connection?.send(AdbPacket("OKAY", id, peer)); return packet
    }
    public func write(_ data: Data) throws {
        try writer.withValue {
            guard let connection else { throw ScrcpyError.message("ADB connection gone") }
            let limit = connection.maxData
            for start in stride(from: 0, to: data.count, by: limit) {
                condition.lock(); let end = Date().addingTimeInterval(15)
                while !ready && !closed { if !condition.wait(until: end) { condition.unlock(); throw ScrcpyError.message("ADB acknowledgement timed out") } }
                guard !closed else { condition.unlock(); throw ScrcpyError.message("ADB stream closed") }
                ready = false; let peer = remote; condition.unlock()
                try connection.send(AdbPacket("WRTE", id, peer, data.subdata(in: start..<min(start + limit, data.count))))
            }
        }
    }
    public func flush(timeout: TimeInterval = 2) throws {
        condition.lock(); defer { condition.unlock() }; let end = Date().addingTimeInterval(timeout)
        while !ready && !closed { if !condition.wait(until: end) { throw ScrcpyError.message("ADB flush timed out") } }
    }
    public func close() {
        condition.lock(); let wasClosed = closed; closed = true; let peer = remote; condition.broadcast(); condition.unlock()
        if !wasClosed { try? connection?.send(AdbPacket("CLSE", id, peer)) }
        connection?.remove(id)
    }
}
