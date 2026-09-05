import AVFoundation
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
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var frame = 0
            input.requestMediaDataWhenReady(on: queue) {
                while input.isReadyForMoreMediaData {
                    guard frame < 60 else {
                        input.markAsFinished()
                        writer.finishWriting {
                            if let error = writer.error {
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
                        input.markAsFinished()
                        writer.cancelWriting()
                        continuation.resume(throwing: CocoaError(.fileWriteUnknown))
                        return
                    }
                    CVPixelBufferLockBaseAddress(pixelBuffer, [])
                    if let bytes = CVPixelBufferGetBaseAddress(pixelBuffer) {
                        memset(bytes, Int32(frame * 3), CVPixelBufferGetDataSize(pixelBuffer))
                    }
                    CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
                    guard adaptor.append(pixelBuffer, withPresentationTime: CMTime(value: Int64(frame), timescale: 30)) else {
                        input.markAsFinished()
                        writer.cancelWriting()
                        continuation.resume(throwing: writer.error ?? CocoaError(.fileWriteUnknown))
                        return
                    }
                    frame += 1
                }
            }
        }
        return url
    }
}
