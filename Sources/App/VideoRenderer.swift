import Foundation
import AVFoundation
import VideoToolbox
import ScrcpyCore

final class VideoRenderer {
    let layer = AVSampleBufferDisplayLayer()
    var onFirstFrame: (() -> Void)?
    var onError: ((String) -> Void)?
    private let queue = DispatchQueue(label: "scrcpy.video.decode", qos: .userInteractive)
    private var decoder: VTDecompressionSession?
    private var format: CMVideoFormatDescription?
    private var sets: [Int: Data] = [:]
    private let hevc: Bool
    private var stopped = false, decoded = false
    init(codec: String) { hevc = codec == "h265"; layer.videoGravity = .resizeAspect; layer.backgroundColor = CGColor(gray: 0, alpha: 1) }
    func consume(_ frame: VideoFrame) {
        queue.sync {
            guard !stopped else { return }
            do { try decode(frame) } catch { stopped = true; onError?(error.localizedDescription) }
        }
    }
    private func decode(_ frame: VideoFrame) throws {
        let units = AnnexB.units(frame.bytes)
        guard !units.isEmpty else { throw ScrcpyError.message("Video packet has no Annex-B NAL units") }
        var changed = false
        for unit in units {
            let type = hevc ? Int((unit[0] >> 1) & 63) : Int(unit[0] & 31)
            if (hevc ? [32,33,34] : [7,8]).contains(type), sets[type] != unit { sets[type] = unit; changed = true }
        }
        if changed { try configure() }
        if frame.config { return }
        guard let decoder, let format else { return }
        let bytes = AnnexB.lengthPrefixed(units)
        var block: CMBlockBuffer?
        try check(CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: bytes.count, blockAllocator: kCFAllocatorDefault, customBlockSource: nil, offsetToData: 0, dataLength: bytes.count, flags: 0, blockBufferOut: &block))
        guard let block else { throw ScrcpyError.message("Cannot allocate video sample") }
        let copied = bytes.withUnsafeBytes { CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: block, offsetIntoDestination: 0, dataLength: bytes.count) }; try check(copied)
        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: CMTime(value: Int64(frame.pts), timescale: 1_000_000), decodeTimeStamp: .invalid)
        var size = bytes.count, sample: CMSampleBuffer?
        try check(CMSampleBufferCreateReady(allocator: kCFAllocatorDefault, dataBuffer: block, formatDescription: format, sampleCount: 1, sampleTimingEntryCount: 1, sampleTimingArray: &timing, sampleSizeEntryCount: 1, sampleSizeArray: &size, sampleBufferOut: &sample))
        guard let sample else { return }
        var info = VTDecodeInfoFlags()
        try check(VTDecompressionSessionDecodeFrame(decoder, sampleBuffer: sample, flags: [], frameRefcon: nil, infoFlagsOut: &info))
        // Keep network back-pressure tied to actual decoding, not an unbounded
        // DispatchQueue of frames when the UI or decoder falls behind.
        try check(VTDecompressionSessionWaitForAsynchronousFrames(decoder))
    }
    private func configure() throws {
        let types = hevc ? [32,33,34] : [7,8]
        guard types.allSatisfy({ sets[$0] != nil }) else { return }
        if let decoder { VTDecompressionSessionWaitForAsynchronousFrames(decoder); VTDecompressionSessionInvalidate(decoder); self.decoder = nil }
        let buffers = types.map { sets[$0]! as NSData }, pointers = buffers.map { $0.bytes.assumingMemoryBound(to: UInt8.self) }, sizes = buffers.map { $0.length }
        var description: CMFormatDescription?
        let status = withExtendedLifetime(buffers) { pointers.withUnsafeBufferPointer { p in sizes.withUnsafeBufferPointer { s -> OSStatus in
            if hevc { return CMVideoFormatDescriptionCreateFromHEVCParameterSets(allocator: kCFAllocatorDefault, parameterSetCount: types.count, parameterSetPointers: p.baseAddress!, parameterSetSizes: s.baseAddress!, nalUnitHeaderLength: 4, extensions: nil, formatDescriptionOut: &description) }
            return CMVideoFormatDescriptionCreateFromH264ParameterSets(allocator: kCFAllocatorDefault, parameterSetCount: types.count, parameterSetPointers: p.baseAddress!, parameterSetSizes: s.baseAddress!, nalUnitHeaderLength: 4, formatDescriptionOut: &description)
        } } }
        try check(status); guard let description else { throw ScrcpyError.message("Video format unavailable") }; format = description
        var callback = VTDecompressionOutputCallbackRecord(decompressionOutputCallback: { context, _, status, _, image, pts, _ in
            guard let context else { return }
            let renderer = Unmanaged<VideoRenderer>.fromOpaque(context).takeUnretainedValue()
            if status == noErr, let image { renderer.present(image, pts: pts) }
            else if status != noErr { renderer.onError?("Video decode error: \(status)") }
        }, decompressionOutputRefCon: Unmanaged.passUnretained(self).toOpaque())
        try check(VTDecompressionSessionCreate(allocator: kCFAllocatorDefault, formatDescription: description, decoderSpecification: nil, imageBufferAttributes: [kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, outputCallback: &callback, decompressionSessionOut: &decoder))
    }
    private func present(_ image: CVPixelBuffer, pts: CMTime) {
        var description: CMVideoFormatDescription?
        guard CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: image, formatDescriptionOut: &description) == noErr, let description else { return }
        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: pts, decodeTimeStamp: .invalid), sample: CMSampleBuffer?
        guard CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: image, formatDescription: description, sampleTiming: &timing, sampleBufferOut: &sample) == noErr, let sample else { return }
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true) as? [NSMutableDictionary], let first = attachments.first { first[kCMSampleAttachmentKey_DisplayImmediately] = true }
        if layer.status == .failed { layer.flush() }
        layer.enqueue(sample)
        if !decoded { decoded = true; onFirstFrame?() }
    }
    private func check(_ status: OSStatus) throws { if status != noErr { throw ScrcpyError.message("VideoToolbox error: \(status)") } }
    func stop() { queue.async { [self] in stopped = true; if let decoder { VTDecompressionSessionWaitForAsynchronousFrames(decoder); VTDecompressionSessionInvalidate(decoder); self.decoder = nil }; layer.flushAndRemoveImage() } }
}
