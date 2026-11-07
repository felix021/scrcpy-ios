import Foundation
import AVFoundation
import ScrcpyCore

final class AudioBridge {
    var onPCM: ((Data) -> Void)?
    var onFailure: ((String, Bool) -> Void)?
    private let queue = DispatchQueue(label: "scrcpy.audio", qos: .userInitiated)
    private var engine: AVAudioEngine?, player: AVAudioPlayerNode?, decoder: AACDecoder?, microphone: AVAudioConverter?
    private var generation = 0
    private var playback = false, recording = false, queued = 0, installedTap = false
    private let pcm = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48000, channels: 2, interleaved: false)!
    func configure(playback: Bool, microphone: Bool) {
        queue.async { [self] in
            guard playback != self.playback || microphone != recording else { return }
            teardown(); self.playback = playback; recording = microphone
            guard playback || microphone else { try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation); return }
            do {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(microphone ? .playAndRecord : .playback, mode: microphone ? .videoChat : .default, options: microphone ? [.defaultToSpeaker, .allowBluetooth] : [])
                try session.setPreferredSampleRate(48000); try session.setPreferredIOBufferDuration(0.02); try session.setActive(true)
                let engine = AVAudioEngine(), player = AVAudioPlayerNode(); self.engine = engine; self.player = player
                engine.attach(player); engine.connect(player, to: engine.mainMixerNode, format: pcm)
                if microphone {
                    let input = engine.inputNode, source = input.outputFormat(forBus: 0)
                    guard source.sampleRate > 0, let destination = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true), let converter = AVAudioConverter(from: source, to: destination) else { throw NSError(domain: "Microphone", code: 1) }
                    self.microphone = converter
                    input.installTap(onBus: 0, bufferSize: 1024, format: source) { [weak self] buffer, _ in
                        guard let output = AVAudioPCMBuffer(pcmFormat: destination, frameCapacity: 4096) else { return }
                        var delivered = false, error: NSError?
                        let status = converter.convert(to: output, error: &error) { _, state in
                            if delivered { state.pointee = .noDataNow; return nil }; delivered = true; state.pointee = .haveData; return buffer
                        }
                        guard status != .error, let samples = output.int16ChannelData?.pointee, output.frameLength > 0 else { return }
                        let data = Data(bytes: samples, count: Int(output.frameLength) * 2)
                        for offset in stride(from: 0, to: data.count, by: 4096) { self?.onPCM?(data.subdata(in: offset..<min(data.count, offset + 4096))) }
                    }
                    installedTap = true
                }
                try engine.start(); if playback { player.play() }
            } catch { onFailure?(error.localizedDescription, microphone); teardown() }
        }
    }
    func consume(_ data: Data, configuration: Bool) {
        queue.async { [self] in
            guard playback, let engine, engine.isRunning else { return }
            do {
                if configuration {
                    decoder = try AACDecoder(configuration: data); return
                }
                guard let decoder, queued < 12, let output = try decoder.decode(data) else { return }
                if output.frameLength > 0 {
                    queued += 1
                    let scheduledGeneration = generation
                    player?.scheduleBuffer(output) { [weak self] in self?.queue.async {
                        guard let self, self.generation == scheduledGeneration else { return }; self.queued = max(0, self.queued - 1)
                    } }
                }
            } catch { onFailure?(error.localizedDescription, false) }
        }
    }
    private func teardown() {
        generation += 1
        if installedTap { engine?.inputNode.removeTap(onBus: 0) }; installedTap = false
        player?.stop(); engine?.stop(); engine = nil; player = nil; microphone = nil; queued = 0
        // Preserve the AAC decoder across route changes; the remote stream is
        // unchanged and need not resend its initial AudioSpecificConfig packet.
    }
    func stop() { queue.async { [self] in playback = false; recording = false; teardown(); decoder = nil; try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) } }
}
