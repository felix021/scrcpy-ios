import Foundation
import ScrcpyCore
import AVFoundation

func option(_ name: String, fallback: String? = nil) -> String? {
    guard let index = CommandLine.arguments.firstIndex(of: name), index + 1 < CommandLine.arguments.count else { return fallback }
    return CommandLine.arguments[index + 1]
}
guard let host = option("--host"), let server = option("--server"), let mic = option("--microphone") else {
    print("Usage: scrcpy-probe --host HOST --port 5555 --server PATH --microphone PATH [--codec h264|h265] [--audio] [--mic-tone] [--touch] [--seconds 8]"); exit(2)
}
var profile = Profile(); profile.host = host; profile.port = Int(option("--port", fallback: "5555")!)!; profile.codec = option("--codec", fallback: "h264")!
profile.forwardAudio = CommandLine.arguments.contains("--audio"); profile.forwardMic = CommandLine.arguments.contains("--mic-tone"); profile.syncRotation = false
let done = DispatchSemaphore(value: 0), lock = NSLock()
var frames = 0, audio = 0, width = 0, height = 0, failed = false
var audioDecoder: AACDecoder?; var decodedAudioSamples = 0; var audioPower = 0.0
let session = try ScrcpySession(profile: profile, identity: AdbIdentity(persistent: false), serverURL: URL(fileURLWithPath: server), microphoneURL: URL(fileURLWithPath: mic))
session.onStatus = { print("STATUS", $0); fflush(stdout) }
session.onWarning = { print("WARNING", $0); fflush(stdout) }
session.onFailure = { print("FAIL", $0.localizedDescription); failed = true; done.signal() }
session.onSize = { w,h in lock.lock(); width = w; height = h; lock.unlock(); print("SIZE",w,h); fflush(stdout) }
session.onVideo = { _ in lock.lock(); frames += 1; lock.unlock() }
session.onAudio = { data,config in
    do {
        if config { audioDecoder = try AACDecoder(configuration: data) }
        else if let buffer = try audioDecoder?.decode(data) {
            lock.lock(); audio += 1; decodedAudioSamples += Int(buffer.frameLength)
            if let samples = buffer.floatChannelData?.pointee { for i in 0..<Int(buffer.frameLength) { audioPower += Double(samples[i] * samples[i]) } }
            lock.unlock()
        }
    } catch { print("AUDIO_FAIL",error.localizedDescription); failed = true }
}
session.onReady = { name in
    print("READY",name); fflush(stdout)
    if CommandLine.arguments.contains("--touch") { session.send(Control.touch(action: 0, pointer: 0, x: width / 2, y: height / 2, width: width, height: height, pressure: 1)); session.send(Control.touch(action: 1, pointer: 0, x: width / 2, y: height / 2, width: width, height: height, pressure: 0)) }
    let duration = Double(option("--seconds", fallback: "8")!)!
    if profile.forwardMic {
        DispatchQueue.global().async {
            for frame in 0..<Int(duration * 50) {
                var pcm = Data()
                for i in 0..<320 { let value = Int16(sin(2 * Double.pi * 997 * Double(frame * 320 + i) / 16000) * 12000); pcm.append(UInt8(truncatingIfNeeded: value)); pcm.append(UInt8(truncatingIfNeeded: value >> 8)) }
                session.microphonePCM(pcm); Thread.sleep(forTimeInterval: 0.02)
            }
        }
    }
    DispatchQueue.global().asyncAfter(deadline: .now() + duration) { done.signal() }
}
session.start()
if done.wait(timeout: .now() + 100) != .success { failed = true; print("TIMEOUT") }
session.disconnect(); Thread.sleep(forTimeInterval: 3)
print("RESULT frames=\(frames) audio=\(audio) size=\(width)x\(height) failed=\(failed) decodedAudioSamples=\(decodedAudioSamples) audioRMS=\(sqrt(audioPower / Double(max(decodedAudioSamples, 1))))")
exit(failed || frames == 0 ? 1 : 0)
