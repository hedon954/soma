@preconcurrency import AVFoundation
import XCTest

/// Synthetic solid-color video. No camera or user media is used.
enum SyntheticVideoFixture {
    static func make() async throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("fixture-\(UUID().uuidString).mp4")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 128,
            AVVideoHeightKey: 128
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: 128,
            kCVPixelBufferHeightKey as String: 128
        ])
        writer.add(input)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        let queue = DispatchQueue(label: "SomaTests.synthetic-video")
        let state = SyntheticVideoWriterState(writer: writer, input: input, adaptor: adaptor)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            input.requestMediaDataWhenReady(on: queue) {
                while state.input.isReadyForMoreMediaData {
                    guard state.frame < 60 else {
                        state.input.markAsFinished()
                        state.writer.finishWriting {
                            if let error = state.writer.error {
                                continuation.resume(throwing: error)
                            } else {
                                continuation.resume()
                            }
                        }
                        return
                    }
                    var pixelBuffer: CVPixelBuffer?
                    let status = CVPixelBufferCreate(kCFAllocatorDefault, 128, 128, kCVPixelFormatType_32ARGB, nil, &pixelBuffer)
                    guard status == kCVReturnSuccess, let pixelBuffer else {
                        state.input.markAsFinished()
                        state.writer.cancelWriting()
                        continuation.resume(throwing: CocoaError(.fileWriteUnknown))
                        return
                    }
                    CVPixelBufferLockBaseAddress(pixelBuffer, [])
                    if let bytes = CVPixelBufferGetBaseAddress(pixelBuffer) {
                        memset(bytes, Int32(state.frame * 3), CVPixelBufferGetDataSize(pixelBuffer))
                    }
                    CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
                    guard state.adaptor.append(pixelBuffer, withPresentationTime: CMTime(value: Int64(state.frame), timescale: 30)) else {
                        state.input.markAsFinished()
                        state.writer.cancelWriting()
                        continuation.resume(throwing: state.writer.error ?? CocoaError(.fileWriteUnknown))
                        return
                    }
                    state.frame += 1
                }
            }
        }
        return url
    }
}

/// AVFoundation resources are handed to one serial writer queue before use.
private final class SyntheticVideoWriterState: @unchecked Sendable {
    let writer: AVAssetWriter
    let input: AVAssetWriterInput
    let adaptor: AVAssetWriterInputPixelBufferAdaptor
    var frame = 0

    init(writer: AVAssetWriter, input: AVAssetWriterInput, adaptor: AVAssetWriterInputPixelBufferAdaptor) {
        self.writer = writer
        self.input = input
        self.adaptor = adaptor
    }
}
