import Foundation
import AVFoundation

/// Shared by the iOS player and the macOS protocol probe, so AAC decoding can
/// be checked against an actual remote stream without a speaker or UI.
public final class AACDecoder {
    public static let outputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48000, channels: 2, interleaved: false)!
    private let converter: AVAudioConverter
    public init(configuration: Data) throws {
        var description = AudioStreamBasicDescription(mSampleRate: 48000, mFormatID: kAudioFormatMPEG4AAC, mFormatFlags: UInt32(MPEG4ObjectID.AAC_LC.rawValue), mBytesPerPacket: 0, mFramesPerPacket: 1024, mBytesPerFrame: 0, mChannelsPerFrame: 2, mBitsPerChannel: 0, mReserved: 0)
        guard let input = AVAudioFormat(streamDescription: &description), let converter = AVAudioConverter(from: input, to: Self.outputFormat) else { throw ScrcpyError.message("AAC decoder unavailable") }
        self.converter = converter; converter.magicCookie = configuration
    }
    public func decode(_ data: Data) throws -> AVAudioPCMBuffer? {
        guard !data.isEmpty, data.count <= 1024 * 1024 else { throw ScrcpyError.message("Invalid AAC frame") }
        let input = AVAudioCompressedBuffer(format: converter.inputFormat, packetCapacity: 1, maximumPacketSize: data.count)
        data.copyBytes(to: input.data.assumingMemoryBound(to: UInt8.self), count: data.count)
        input.byteLength = UInt32(data.count); input.packetCount = 1
        input.packetDescriptions?.pointee = AudioStreamPacketDescription(mStartOffset: 0, mVariableFramesInPacket: 1024, mDataByteSize: UInt32(data.count))
        guard let output = AVAudioPCMBuffer(pcmFormat: Self.outputFormat, frameCapacity: 4096) else { throw ScrcpyError.message("Cannot allocate audio buffer") }
        var delivered = false, error: NSError?
        let status = converter.convert(to: output, error: &error) { _, state in
            if delivered { state.pointee = .noDataNow; return nil }; delivered = true; state.pointee = .haveData; return input
        }
        if status == .error { throw error ?? ScrcpyError.message("AAC conversion failed") }
        return output.frameLength > 0 ? output : nil
    }
}
