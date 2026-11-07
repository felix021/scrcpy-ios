import SwiftUI
import AVFoundation
import ScrcpyCore

func L(_ chinese: String, _ english: String) -> String {
    let preference = UserDefaults.standard.string(forKey: "language") ?? "system"
    return (preference == "zh" || preference == "system" && Locale.preferredLanguages.first?.hasPrefix("zh") == true) ? chinese : english
}

private struct SavedProfiles: Codable { var last = Profile(); var profiles: [Profile] = [] }
private final class ProfileStore {
    let directory: URL
    var file: URL { directory.appendingPathComponent("profiles.json") }
    init() throws {
        directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Scrcpy", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var resource = URLResourceValues(); resource.isExcludedFromBackup = true; var url = directory; try url.setResourceValues(resource)
    }
    func load() throws -> SavedProfiles { if !FileManager.default.fileExists(atPath: file.path) { return SavedProfiles() }; return try JSONDecoder().decode(SavedProfiles.self, from: Data(contentsOf: file)) }
    func save(_ value: SavedProfiles) throws { try JSONEncoder().encode(value).write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]) }
}

@MainActor final class AppModel: ObservableObject {
    @Published var profile = Profile()
    @Published var host = ""
    @Published var port = "5555"
    @Published var size = "1600"
    @Published var bitrate = "6"
    @Published var fps = "60"
    @Published var language = UserDefaults.standard.string(forKey: "language") ?? "system" { didSet { UserDefaults.standard.set(language, forKey: "language") } }
    @Published var profiles: [Profile] = []
    @Published var active = false
    @Published var ready = false
    @Published var keyboardVisible = false
    @Published var status = ""
    @Published var notice: String?
    @Published var videoWidth = 1080
    @Published var videoHeight = 2340
    @Published var renderer = VideoRenderer(codec: "h264")
    @Published var deviceName = ""
    var effectiveLocale: Locale { language == "system" ? .current : Locale(identifier: language == "zh" ? "zh-Hans" : "en") }
    private var store: ProfileStore?, session: ScrcpySession?, audio: AudioBridge?
    private var generation = UUID()
    private var landscape = false
    var cancelInput: (() -> Void)?
    var resetModifiers: (() -> Void)?
    init() {
        do { let store = try ProfileStore(); self.store = store
            #if DEBUG
            if CommandLine.arguments.contains("--ui-test-reset") { try? FileManager.default.removeItem(at: store.file) }
            #endif
            let saved = try store.load(); profiles = saved.profiles; apply(saved.last)
        } catch { notice = L("无法读取已保存配置：", "Cannot read saved profiles: ") + error.localizedDescription }
        #if DEBUG
        let env = ProcessInfo.processInfo.environment
        if let testHost = env["SCRCPY_TEST_HOST"] { host = testHost; port = env["SCRCPY_TEST_PORT"] ?? "5555"; profile.forwardAudio = env["SCRCPY_TEST_AUDIO"] == "1"; profile.syncRotation = false; if let codec = env["SCRCPY_TEST_CODEC"] { profile.codec = codec } }
        if CommandLine.arguments.contains("--autoconnect") { DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.connect() } }
        #endif
    }
    func hostBinding() -> Binding<String> { Binding(get: { self.host }, set: { if self.host != $0 { self.host = $0; self.profile.name = ""; self.profile.id = UUID() } }) }
    func portBinding() -> Binding<String> { Binding(get: { self.port }, set: { if self.port != $0 { self.port = $0; self.profile.name = ""; self.profile.id = UUID() } }) }
    private func draft() throws -> Profile {
        guard let port = Int(port), let size = Int(size), let bitrate = Int(bitrate), let fps = Int(fps) else { throw ScrcpyError.message(L("端口与画面参数必须是整数", "Port and video values must be integers")) }
        var value = profile; value.host = host.trimmingCharacters(in: .whitespacesAndNewlines); value.port = port; value.maxSize = size; value.bitrate = bitrate; value.fps = fps
        try value.validate(); return value
    }
    func quality(_ index: Int) { size = ["1024","1600","2400"][index]; bitrate = ["2","6","12"][index]; fps = ["30","60","60"][index]; profile.codec = "h264" }
    var qualityName: String {
        let values = [("1024","2","30"),("1600","6","60"),("2400","12","60")]
        if profile.codec == "h264", let i = values.firstIndex(where: { $0 == (size,bitrate,fps) }) { return [L("省流","Economy"),L("均衡","Balanced"),L("高清","High")][i] }
        return L("自定义","Custom")
    }
    func apply(_ value: Profile) { profile = value; host = value.host; port = String(value.port); size = String(value.maxSize); bitrate = String(value.bitrate); fps = String(value.fps) }
    @discardableResult func save(name: String) -> Bool {
        do {
            let name = name.trimmingCharacters(in: .whitespacesAndNewlines); guard !name.isEmpty else { throw ScrcpyError.message(L("请输入配置名称", "Enter a profile name")) }
            var value = try draft(); value.name = name
            if let old = profiles.first(where: { $0.name == name }) { value.id = old.id }
            profiles.removeAll { $0.id == value.id || $0.name == name }; profiles.append(value); profile = value; try persist(); return true
        } catch { notice = error.localizedDescription; return false }
    }
    func delete(_ value: Profile) { profiles.removeAll { $0.id == value.id }; if profile.id == value.id { profile.name = ""; profile.id = UUID() }; do { try persist() } catch { notice = error.localizedDescription } }
    private func persist() throws { guard let store else { throw ScrcpyError.message(L("配置存储不可用", "Profile storage unavailable")) }; try store.save(SavedProfiles(last: profile, profiles: profiles)) }
    private func persistRuntime() {
        if let index = profiles.firstIndex(where: { $0.id == profile.id && $0.host == profile.host && $0.port == profile.port }) { profiles[index] = profile }
        do { try persist() } catch { notice = error.localizedDescription }
    }
    func option(_ keyPath: WritableKeyPath<Profile, Bool>) -> Binding<Bool> { Binding(get: { self.profile[keyPath: keyPath] }, set: { self.setOption(keyPath, value: $0) }) }
    func setOption(_ keyPath: WritableKeyPath<Profile, Bool>, value: Bool) {
        if keyPath == \.forwardMic, value && active {
            let token = generation
            AVAudioSession.sharedInstance().requestRecordPermission { [weak self] allowed in Task { @MainActor in
                guard let self, self.generation == token, self.active else { return }
                if allowed { self.applyOption(keyPath, value: true) } else { self.notice = L("录音权限被拒绝，麦克风保持关闭", "Microphone permission denied; forwarding stays off") }
            } }; return
        }
        applyOption(keyPath, value: value)
    }
    private func applyOption(_ keyPath: WritableKeyPath<Profile, Bool>, value: Bool) {
        if profile.viewOnly && (keyPath == \.forwardMic || keyPath == \.syncRotation) && active { return }
        profile[keyPath: keyPath] = value
        guard active else { return }
        switch keyPath {
        case \.forwardAudio: audio?.configure(playback: profile.forwardAudio, microphone: profile.forwardMic && !profile.viewOnly); session?.setAudio(value)
        case \.forwardMic: audio?.configure(playback: profile.forwardAudio, microphone: profile.forwardMic && !profile.viewOnly); session?.setMicrophone(value)
        case \.syncRotation: session?.setSyncRotation(value)
        case \.stayAwake: session?.setAwake(value)
        case \.showNavigation: cancelInput?()
        default: break
        }
        persistRuntime()
    }
    func connect() {
        guard !active else { return }
        do {
            let value = try draft()
            if value.forwardMic && !value.viewOnly {
                let token = generation
                AVAudioSession.sharedInstance().requestRecordPermission { [weak self] allowed in Task { @MainActor in
                    guard let self, !self.active, self.generation == token else { return }
                    if allowed { self.begin(value) } else { self.notice = L("请允许录音，或关闭麦克风转发后连接", "Allow microphone access, or turn forwarding off to connect") }
                } }
            } else { begin(value) }
        } catch { notice = error.localizedDescription }
    }
    private func begin(_ value: Profile) {
        do {
            guard let server = Bundle.main.url(forResource: "scrcpy-server", withExtension: "jar"), let microphone = Bundle.main.url(forResource: "microphone-server", withExtension: "jar") else { throw ScrcpyError.message(L("缺少远端服务资源，请先运行构建脚本", "Missing Android services; run the resource preparation script")) }
            let core = try ScrcpySession(profile: value, identity: AdbIdentity(), serverURL: server, microphoneURL: microphone)
            generation = UUID(); let token = generation; profile = value; if value.viewOnly { profile.forwardMic = false }; try persist()
            let renderer = VideoRenderer(codec: value.codec), audio = AudioBridge()
            self.renderer = renderer; self.audio = audio; session = core; active = true; ready = false; status = L("正在连接…", "Connecting…"); notice = nil; keyboardVisible = false
            UIApplication.shared.isIdleTimerDisabled = true
            renderer.onFirstFrame = { [weak self] in Task { @MainActor in guard let self, self.generation == token else { return }; self.ready = true; self.status = self.profile.viewOnly ? L("仅观看","View only") : L("已连接","Connected") } }
            renderer.onError = { [weak self] error in Task { @MainActor in guard let self, self.generation == token else { return }; self.disconnect(message: error) } }
            core.onVideo = { renderer.consume($0) }; core.onAudio = { audio.consume($0, configuration: $1) }
            core.onSize = { [weak self] w,h in Task { @MainActor in guard let self, self.generation == token else { return }; self.cancelInput?(); self.videoWidth = w; self.videoHeight = h } }
            core.onReady = { [weak self] name in Task { @MainActor in guard let self, self.generation == token else { return }; self.deviceName = name } }
            core.onStatus = { [weak self] text in Task { @MainActor in guard let self, self.generation == token, !self.ready else { return }; switch text {
                case "Connecting to ADB · allow debugging on Android": self.status = L("正在连接 ADB · 请在 Android 允许调试","Connecting to ADB · allow debugging on Android")
                case "Preparing remote services": self.status = L("正在准备远端服务","Preparing remote services")
                default: self.status = text.hasPrefix("Receiving ") ? L("正在接收画面","Receiving video") : text
                } } }
            core.onFailure = { [weak self] error in Task { @MainActor in guard let self, self.generation == token else { return }; self.disconnect(message: error.localizedDescription) } }
            core.onWarning = { [weak self] text in Task { @MainActor in guard let self, self.generation == token else { return }; self.notice = text } }
            core.onSettingFailed = { [weak self, weak core] _ in Task { @MainActor in
                guard let self, let core, self.generation == token else { return }
                self.profile.forwardAudio = core.audioEnabled; self.profile.forwardMic = core.microphoneEnabled
                audio.configure(playback: self.profile.forwardAudio, microphone: self.profile.forwardMic); self.persistRuntime()
            } }
            audio.onPCM = { [weak core] in core?.microphonePCM($0) }
            audio.onFailure = { [weak self] message,mic in Task { @MainActor in
                guard let self, self.generation == token else { return }; self.notice = message
                self.applyOption(mic ? \.forwardMic : \.forwardAudio, value: false)
            } }
            audio.configure(playback: value.forwardAudio, microphone: value.forwardMic && !value.viewOnly)
            core.orientation(landscape: landscape); core.start()
            DispatchQueue.main.asyncAfter(deadline: .now() + 90) { [weak self] in guard let self, self.generation == token, !self.ready else { return }; self.disconnect(message: L("等待远端画面超时", "Timed out waiting for decoded video")) }
        } catch { notice = error.localizedDescription }
    }
    func disconnect(message: String? = nil) {
        cancelInput?(); resetModifiers?(); let old = session; session = nil; generation = UUID(); active = false; ready = false; keyboardVisible = false
        audio?.stop(); audio = nil; renderer.stop(); old?.disconnect(); UIApplication.shared.isIdleTimerDisabled = false
        if let message { notice = message }
    }
    func orientation(_ landscape: Bool) { guard self.landscape != landscape else { return }; cancelInput?(); resetModifiers?(); self.landscape = landscape; session?.orientation(landscape: landscape) }
    func rotate(right: Bool) { cancelInput?(); session?.rotate(right: right) }
    func key(_ code: UInt32, meta: UInt32 = 0) { if !profile.viewOnly { session?.key(code, meta: meta) } }
    func touch(_ action: UInt8, pointer: UInt64, x: Int, y: Int, pressure: Double) { session?.send(Control.touch(action: action, pointer: pointer, x: x, y: y, width: videoWidth, height: videoHeight, pressure: pressure)) }
    func navigate(_ edge: Int) { switch edge { case 0,1: key(4); case 2: key(3); default: session?.expandSettings() } }
    func text(_ text: String) { do { try session?.paste(text) } catch { notice = error.localizedDescription } }
    func paste() { if let text = UIPasteboard.general.string { self.text(text) } }
    func toggleKeyboard() { cancelInput?(); resetModifiers?(); keyboardVisible.toggle() }
}
