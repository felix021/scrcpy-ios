import Foundation

public final class ScrcpySession {
    public var onStatus: ((String) -> Void)?
    public var onReady: ((String) -> Void)?
    public var onSize: ((Int, Int) -> Void)?
    public var onVideo: ((VideoFrame) -> Void)?
    public var onAudio: ((Data, Bool) -> Void)?
    public var onWarning: ((String) -> Void)?
    public var onFailure: ((Error) -> Void)?
    public var onSettingFailed: ((String) -> Void)?
    private let lock = NSLock()
    private var profile: Profile
    private let clientName: String
    private let identity: AdbIdentity
    private let serverURL: URL, microphoneURL: URL
    private var connection: AdbConnection?, control: AdbStream?, settings: RemoteSettings?
    private var videoShell: AdbStream?, audioShell: AdbStream?, audioStream: AdbStream?, microphoneShell: AdbStream?, microphoneStream: AdbStream?
    private var closing = false, connected = false, rendered = false, microphoneUploaded = false
    private var audioEpoch = 0, microphoneEpoch = 0, controlPending = 0, micPending = 0
    private var audioQueue = DispatchQueue(label: "scrcpy.audio.settings"), micQueue = DispatchQueue(label: "scrcpy.mic.settings")
    private let controlQueue = DispatchQueue(label: "scrcpy.control"), pcmQueue = DispatchQueue(label: "scrcpy.mic.pcm")
    private let id = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8)).lowercased()
    private var serverPath: String { "/data/local/tmp/scrcpy-ios-\(id).jar" }
    private var micPath: String { "/data/local/tmp/scrcpy-ios-mic-\(id).jar" }
    private var lastLandscape = false
    public init(profile: Profile, identity: AdbIdentity, serverURL: URL, microphoneURL: URL, clientName: String = "scrcpy-ios") throws {
        self.clientName=clientName
        try profile.validate(); var safe = profile; safe.forwardMic = profile.forwardMic && !profile.viewOnly; self.profile = safe; self.identity = identity; self.serverURL = serverURL; self.microphoneURL = microphoneURL
    }
    private var active: Bool { lock.withValue { !closing } }
    public func start() {
        Thread.detachNewThread { [self] in
            do { try run() } catch { fail(error) }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 90) { [weak self] in
            guard let self else { return }; if self.lock.withValue({ !self.rendered && !self.closing }) { self.fail(ScrcpyError.message("Timed out waiting for remote video")) }
        }
    }
    private func owned(_ command: String) -> String {
        command + " </dev/null & child=$!; trap 'kill \"$child\" 2>/dev/null; wait \"$child\" 2>/dev/null' EXIT; trap 'exit' HUP INT TERM; while IFS= read -r stop; do [ \"$stop\" = q ] && break; done"
    }
    private func drain(_ shell: AdbStream, name: String) {
        Thread.detachNewThread { [weak self] in
            do { while self?.active == true { let bytes = try shell.readChunk(); let text = String(decoding: bytes, as: UTF8.self); if text.contains("ERROR") { self?.onWarning?("\(name): \(text.prefix(400))") } } } catch { }
        }
    }
    private func run() throws {
        let profile = lock.withValue { self.profile }
        onStatus?("Connecting to ADB · allow debugging on Android")
        let adb = try AdbConnection(host: profile.host, port: profile.port, identity: identity, clientName: clientName)
        try lock.withValue { guard !closing else { throw ScrcpyError.message("Cancelled") }; connection = adb }
        adb.onClose = { [weak self] error in self?.fail(error) }
        try adb.connect(); guard active else { return }
        onStatus?("Preparing remote services")
        let remote = try RemoteSettings(connection: adb, serverPath: serverPath, micPath: micPath, warning: { [weak self] in self?.onWarning?($0) }, failure: { [weak self] in self?.fail($0) })
        lock.withValue { settings = remote }; guard active else { remote.cancel(); return }
        remote.send(profile.stayAwake ? "w1" : "w0")
        if profile.syncRotation && !profile.viewOnly { remote.send(lock.withValue { lastLandscape } ? "1" : "0") }
        try push(adb, path: serverPath, data: Data(contentsOf: serverURL))
        guard active else { return }
        // The high bit is reserved by scrcpy's scid parser.
        let scid = String(format: "%08x", UInt32.random(in: 1...0x7fffffff))
        let command = "CLASSPATH=\(serverPath) app_process / com.genymobile.scrcpy.Server 5.0.1 scid=\(scid) tunnel_forward=true audio=false video=true cleanup=false clipboard_autosync=false power_on=true max_size=\(profile.maxSize) video_bit_rate=\(profile.bitrate * 1000000) max_fps=\(profile.fps) video_codec=\(profile.codec) control=\(!profile.viewOnly) stay_awake=false"
        let shell = try adb.open("shell:" + owned(command)); lock.withValue { videoShell = shell }; drain(shell, name: "Video")
        let video = try openSocket(adb, name: "scrcpy_" + scid)
        guard try video.read(1)[0] == 0 else { throw ScrcpyError.message("Invalid video handshake") }
        if !profile.viewOnly {
            let channel = try adb.open("localabstract:scrcpy_" + scid)
            lock.withValue { control = channel }
            Thread.detachNewThread { [weak self] in do { while self?.active == true { _ = try channel.readChunk() } } catch { if self?.active == true { self?.fail(error) } } }
        }
        let name = String(decoding: try video.read(64), as: UTF8.self).replacingOccurrences(of: "\0", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        let codec = try video.read(4).uint32BE()
        guard codec == 0x68323634 || codec == 0x68323635 else { throw ScrcpyError.message("Unsupported video codec") }
        let epochs = lock.withValue { () -> (Int, Int) in connected = true; return (audioEpoch, microphoneEpoch) }
        audioQueue.async { [weak self] in self?.updateAudio(epoch: epochs.0) }
        micQueue.async { [weak self] in self?.updateMicrophone(epoch: epochs.1) }
        onStatus?("Receiving \(name)")
        while active {
            let header = try video.read(12), flags = header.uint64BE(), count = header.uint32BE(8)
            if flags & (1 << 63) != 0 {
                let width = Int(header.uint32BE(4)), height = Int(count)
                guard width > 0 && height > 0 && width <= 16384 && height <= 16384 else { throw ScrcpyError.message("Invalid video dimensions") }
                onSize?(width, height); continue
            }
            guard count > 0 && count <= 16 * 1024 * 1024 else { throw ScrcpyError.message("Invalid video frame") }
            let frame = VideoFrame(bytes: try video.read(Int(count)), pts: flags & ((1 << 61) - 1), config: flags & (1 << 62) != 0, keyframe: flags & (1 << 61) != 0)
            onVideo?(frame)
            if !frame.config && lock.withValue({ !rendered }) { lock.withValue { rendered = true }; onReady?(name) }
        }
    }
    private func openSocket(_ adb: AdbConnection, name: String) throws -> AdbStream {
        for _ in 0..<100 {
            guard active else { throw ScrcpyError.message("Cancelled") }
            if let stream = try? adb.open("localabstract:" + name, timeout: 1) { return stream }
            Thread.sleep(forTimeInterval: 0.08)
        }
        throw ScrcpyError.message("Remote service did not create its socket")
    }
    private func push(_ adb: AdbConnection, path: String, data: Data) throws {
        guard active else { throw ScrcpyError.message("Cancelled") }
        let sync = try adb.open("sync:"); defer { sync.close() }
        func chunk(_ tag: String, _ bytes: Data) throws { var out = Data(tag.utf8); out.appendLE(UInt32(bytes.count)); out += bytes; try sync.write(out) }
        try chunk("SEND", Data((path + ",33216").utf8))
        let limit = min(65528, adb.maxData - 8)
        for start in stride(from: 0, to: data.count, by: limit) { guard active else { throw ScrcpyError.message("Cancelled") }; try chunk("DATA", data.subdata(in: start..<min(data.count, start + limit))) }
        var done = Data("DONE".utf8); done.appendLE(UInt32(Date().timeIntervalSince1970)); try sync.write(done)
        let answer = try sync.read(8)
        guard String(decoding: answer.prefix(4), as: UTF8.self) == "OKAY" else { throw ScrcpyError.message("Remote service upload failed") }
    }
    public func send(_ bytes: Data) {
        let accepted = lock.withValue { () -> Bool in guard !closing, !profile.viewOnly, control != nil else { return false }; controlPending += 1; return controlPending <= 256 }
        guard accepted else { if lock.withValue({ controlPending > 256 }) { fail(ScrcpyError.message("Control queue congested")) }; return }
        controlQueue.async { [weak self] in
            guard let self else { return }; defer { self.lock.withValue { self.controlPending -= 1 } }
            do { try self.lock.withValue { self.control }?.write(bytes) } catch { self.fail(error) }
        }
    }
    public func key(_ code: UInt32, meta: UInt32 = 0) { send(Control.chord(code, meta: meta)) }
    public func paste(_ text: String) throws { send(try Control.paste(text)) }
    public func expandSettings() { send(Data([6])) }
    public func orientation(landscape: Bool) {
        let remote = lock.withValue { () -> RemoteSettings? in lastLandscape = landscape; return !closing && profile.syncRotation && !profile.viewOnly ? settings : nil }
        remote?.send(landscape ? "1" : "0")
    }
    public func setSyncRotation(_ value: Bool) {
        let tuple = lock.withValue { () -> (RemoteSettings?, Bool) in profile.syncRotation = value; return (!closing && !profile.viewOnly ? settings : nil, lastLandscape) }
        tuple.0?.send(value ? (tuple.1 ? "1" : "0") : "r")
    }
    public func rotate(right: Bool) { lock.withValue { !closing && !profile.viewOnly ? settings : nil }?.send(right ? "R" : "L") }
    public func setAwake(_ value: Bool) { let remote = lock.withValue { () -> RemoteSettings? in profile.stayAwake = value; return !closing ? settings : nil }; remote?.send(value ? "w1" : "w0") }
    public func setAudio(_ value: Bool) {
        let epoch = lock.withValue { () -> Int in profile.forwardAudio = value; audioEpoch += 1; return audioEpoch }
        audioQueue.async { [weak self] in self?.updateAudio(epoch: epoch) }
    }
    private func updateAudio(epoch: Int) {
        guard lock.withValue({ !closing && connected && audioEpoch == epoch }) else { return }
        let old = lock.withValue { () -> (AdbStream?, AdbStream?) in let pair = (audioShell, audioStream); audioShell = nil; audioStream = nil; return pair }
        try? old.0?.write(Data("q\n".utf8)); old.0?.close(); old.1?.close()
        guard let adb = lock.withValue({ !closing && connected && profile.forwardAudio && audioEpoch == epoch ? connection : nil }) else { return }
        var shell: AdbStream?, stream: AdbStream?
        do {
            let scid = String(format: "%08x", UInt32.random(in: 1...0x7fffffff))
            shell = try adb.open("shell:" + owned("CLASSPATH=\(serverPath) app_process / com.genymobile.scrcpy.Server 5.0.1 scid=\(scid) tunnel_forward=true video=false audio=true audio_codec=aac control=false cleanup=false send_device_meta=false"))
            drain(shell!, name: "Audio"); stream = try openSocket(adb, name: "scrcpy_" + scid)
            let committed = lock.withValue { () -> Bool in guard !closing && audioEpoch == epoch && profile.forwardAudio else { return false }; audioShell = shell; audioStream = stream; return true }
            guard committed else { shell?.close(); stream?.close(); return }
            let input = stream!
            Thread.detachNewThread { [weak self] in
                do {
                    guard try input.read(1)[0] == 0, try input.read(4).uint32BE() == 0x00616163 else { throw ScrcpyError.message("Remote audio requires Android 11+ and an unlocked device") }
                    while self?.audioCurrent(epoch) == true {
                        let header = try input.read(12), length = header.uint32BE(8)
                        guard length > 0 && length <= 1024 * 1024 else { throw ScrcpyError.message("Invalid audio frame") }
                        let bytes = try input.read(Int(length)); if self?.audioCurrent(epoch) == true { self?.onAudio?(bytes, header.uint64BE() & (1 << 62) != 0) }
                    }
                } catch { self?.audioFailed(error, epoch: epoch) }
                input.close()
            }
        } catch {
            shell?.close(); stream?.close()
            audioFailed(error, epoch: epoch)
        }
    }
    public var audioEnabled: Bool { lock.withValue { profile.forwardAudio } }
    public var microphoneEnabled: Bool { lock.withValue { profile.forwardMic } }
    private func audioFailed(_ error: Error, epoch: Int) {
        let next = lock.withValue { () -> Int? in guard !closing && audioEpoch == epoch && profile.forwardAudio else { return nil }; profile.forwardAudio = false; audioEpoch += 1; return audioEpoch }
        guard let next else { return }; onWarning?(error.localizedDescription); onSettingFailed?("audio")
        audioQueue.async { [weak self] in self?.updateAudio(epoch: next) }
    }
    private func microphoneFailed(_ error: Error, epoch: Int) {
        let next = lock.withValue { () -> Int? in guard !closing && microphoneEpoch == epoch && profile.forwardMic else { return nil }; profile.forwardMic = false; microphoneEpoch += 1; return microphoneEpoch }
        guard let next else { return }; onWarning?(error.localizedDescription); onSettingFailed?("microphone")
        micQueue.async { [weak self] in self?.updateMicrophone(epoch: next) }
    }
    private func audioCurrent(_ epoch: Int) -> Bool { lock.withValue { !closing && profile.forwardAudio && audioEpoch == epoch } }
    public func setMicrophone(_ value: Bool) {
        let epoch = lock.withValue { () -> Int in profile.forwardMic = value && !profile.viewOnly; microphoneEpoch += 1; return microphoneEpoch }
        micQueue.async { [weak self] in self?.updateMicrophone(epoch: epoch) }
    }
    private func updateMicrophone(epoch: Int) {
        guard lock.withValue({ !closing && connected && microphoneEpoch == epoch }) else { return }
        let old = lock.withValue { () -> (AdbStream?, AdbStream?) in let pair = (microphoneShell, microphoneStream); microphoneShell = nil; microphoneStream = nil; return pair }
        old.1?.close(); old.0?.close()
        guard let adb = lock.withValue({ !closing && connected && profile.forwardMic && microphoneEpoch == epoch ? connection : nil }) else { return }
        var shell: AdbStream?, stream: AdbStream?
        do {
            if !lock.withValue({ microphoneUploaded }) { try push(adb, path: micPath, data: Data(contentsOf: microphoneURL)); lock.withValue { microphoneUploaded = true } }
            shell = try adb.open("shell:CLASSPATH=\(micPath) app_process / cn.felix021.scrcpy.MicServer scrcpy_ios_mic_\(id) \(micPath) keep")
            let ready = DispatchSemaphore(value: 0), logLock = NSLock(); var text = ""
            let logStream = shell!
            Thread.detachNewThread {
                do { while true { let value = try logStream.readChunk(); let line = String(decoding: value, as: UTF8.self); logLock.withValue { text = String((text + line).suffix(3000)) }; if line.contains("MIC_READY") { ready.signal() } } } catch { ready.signal() }
            }
            guard ready.wait(timeout: .now() + 15) == .success, logLock.withValue({ text.contains("MIC_READY") }) else { throw ScrcpyError.message("Remote microphone audio routing is unavailable") }
            stream = try openSocket(adb, name: "scrcpy_ios_mic_" + id)
            let committed = lock.withValue { () -> Bool in guard !closing && microphoneEpoch == epoch && profile.forwardMic else { return false }; microphoneShell = shell; microphoneStream = stream; return true }
            if !committed { shell?.close(); stream?.close() }
        } catch {
            shell?.close(); stream?.close()
            microphoneFailed(error, epoch: epoch)
        }
    }
    public func microphonePCM(_ bytes: Data) {
        guard !bytes.isEmpty && bytes.count <= 4096 && bytes.count % 2 == 0 else { return }
        let channel = lock.withValue { () -> AdbStream? in guard !closing && profile.forwardMic && micPending < 4, let channel = microphoneStream else { return nil }; micPending += 1; return channel }
        guard let channel else { return }
        var packet = Data(); packet.appendBE(UInt16(bytes.count)); packet += bytes
        pcmQueue.async { [weak self] in defer { self?.lock.withValue { self?.micPending -= 1 } }; try? channel.write(packet) }
    }
    private func fail(_ error: Error) {
        let shouldReport = lock.withValue { !closing }
        if shouldReport { disconnect(graceful: false); onFailure?(error) }
    }
    public func disconnect(graceful: Bool = true) {
        let owned: (AdbConnection?, RemoteSettings?, [AdbStream])? = lock.withValue {
            guard !closing else { return nil }; closing = true; audioEpoch += 1; microphoneEpoch += 1
            return (connection, settings, [audioShell, audioStream, microphoneShell, microphoneStream].compactMap { $0 })
        }
        guard let owned else { return }
        owned.2.forEach { $0.close() }
        if !graceful { owned.1?.cancel(); owned.0?.close(); return }
        DispatchQueue.global().async { [self] in
            owned.1?.finish()
            let done = DispatchSemaphore(value: 0)
            controlQueue.async { [weak self] in try? self?.control?.flush(timeout: 0.5); owned.0?.close(); done.signal() }
            if done.wait(timeout: .now() + 2) != .success { owned.0?.close() }
        }
    }
}
