@preconcurrency import AVFoundation
import CoreGraphics
import Foundation

private let frameRate: Int32 = 30
private let size = 384

private enum Exercise: String, Codable, Sendable {
    case squat, curl, pushUp = "push_up", overheadPress = "overhead_press"
}

private struct Repetition: Sendable {
    let exercise: Exercise
    let start: Int
    let turn: Int
    let holdUntil: Int
    let end: Int

    init(_ exercise: Exercise, _ start: Int, _ turn: Int, _ end: Int, holdUntil: Int? = nil) {
        self.exercise = exercise
        self.start = start
        self.turn = turn
        self.holdUntil = holdUntil ?? turn
        self.end = end
    }

    func position(at frame: Int) -> CGFloat {
        let progress: Double = switch frame {
        case start ..< turn: Double(frame - start) / Double(turn - start)
        case turn ... holdUntil: 1
        case holdUntil ..< end: Double(end - frame) / Double(end - holdUntil)
        default: 0
        }
        return CGFloat(0.5 - cos(progress * .pi) * 0.5)
    }
}

private struct Clip: Sendable {
    let scenario: String
    let repetitions: [Repetition]
    let hidden: Range<Int>?
    let mirrored: Bool

    init(_ scenario: String, _ repetitions: [Repetition] = [], hidden: Range<Int>? = nil, mirrored: Bool = false) {
        self.scenario = scenario
        self.repetitions = repetitions
        self.hidden = hidden
        self.mirrored = mirrored
    }

    var frames: Int {
        max(110, (repetitions.last?.end ?? 0) + 24)
    }

    func repetition(at frame: Int) -> Repetition? {
        for index in repetitions.indices.dropFirst().reversed() {
            let next = repetitions[index]
            let previous = repetitions[index - 1]
            if frame >= max(previous.end + 1, next.start - 12) {
                return next
            }
        }
        return repetitions.first
    }
}

private let clips: [Clip] = [
    .init("normal", [.init(.squat, 17, 48, 84)]),
    .init("fast_descent", [.init(.squat, 21, 30, 58)]),
    .init("slow_descent", [.init(.squat, 20, 94, 133)]),
    .init("paused", [.init(.squat, 15, 43, 111, holdUntil: 76)]),
    .init("short_rep", [.init(.curl, 29, 36, 45)]),
    .init("mirrored", [.init(.curl, 19, 45, 70)], mirrored: true),
    .init("asymmetric_tempo", [.init(.curl, 17, 29, 107)]),
    .init("two_tempo_changes", [.init(.curl, 13, 40, 62), .init(.curl, 74, 86, 113)]),
    .init("fast_descent", [.init(.pushUp, 22, 32, 61)]),
    .init("slow_descent", [.init(.pushUp, 17, 89, 133)], mirrored: true),
    .init("paused", [.init(.pushUp, 12, 53, 112, holdUntil: 86)]),
    .init("short_rep", [.init(.overheadPress, 19, 31, 49)]),
    .init("slow_descent", [.init(.overheadPress, 27, 63, 149)]),
    .init("occluded_turn", [.init(.squat, 21, 57, 96)], hidden: 43 ..< 73),
    .init("occluded_finish", [.init(.pushUp, 20, 55, 94)], hidden: 80 ..< 106),
    .init("occluded_start", [.init(.curl, 22, 47, 89)], hidden: 15 ..< 35, mirrored: true),
    .init("mixed_exercises", [.init(.squat, 16, 43, 70), .init(.curl, 109, 130, 157)]),
    .init("mixed_exercises", [.init(.overheadPress, 17, 48, 75), .init(.pushUp, 116, 146, 180)]),
    .init("no_repetition"),
    .init("no_repetition_with_occlusion", hidden: 30 ..< 70, mirrored: true)
]

private struct TimingEvent: Codable {
    let exercise: Exercise
    let phase: String
    let seconds: Double
}

private struct TimeRange: Codable {
    let start: Double
    let end: Double
}

private struct GroundTruth: Codable {
    let clip: String
    let scenario: String
    let duration: Double
    let events: [TimingEvent]
    let occlusions: [TimeRange]

    init(clip: Clip, file: String) {
        self.clip = file
        scenario = clip.scenario
        duration = Self.seconds(clip.frames)
        events = clip.repetitions.flatMap { rep in
            [(rep.start, "rep_start"), (rep.turn, "direction_change"), (rep.end, "rep_finish")].compactMap { frame, phase in
                guard clip.hidden?.contains(frame) != true else { return nil }
                return TimingEvent(exercise: rep.exercise, phase: phase, seconds: Self.seconds(frame))
            }
        }
        occlusions = clip.hidden.map { [TimeRange(start: Self.seconds($0.lowerBound), end: Self.seconds($0.upperBound))] } ?? []
    }

    private static func seconds(_ frames: Int) -> Double {
        Double(frames) / Double(frameRate)
    }
}

private extension CGContext {
    func line(_ points: [CGPoint], thickness: CGFloat, color: CGColor) {
        setStrokeColor(color)
        setLineWidth(thickness)
        setLineCap(.round)
        setLineJoin(.round)
        addLines(between: points)
        strokePath()
    }

    func head(_ point: CGPoint, color: CGColor) {
        setFillColor(color)
        fillEllipse(in: CGRect(x: point.x - 18, y: point.y - 21, width: 36, height: 42))
    }
}

private func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
    CGPoint(x: x, y: y)
}

private func draw(_ clip: Clip, frame: Int, into canvas: CGContext) {
    canvas.setFillColor(gray: 0.94, alpha: 1)
    canvas.fill(CGRect(x: 0, y: 0, width: size, height: size))
    canvas.setFillColor(gray: 0.81, alpha: 1)
    canvas.fill(CGRect(x: 0, y: 0, width: size, height: 65))
    if clip.mirrored {
        canvas.translateBy(x: CGFloat(size), y: 0)
        canvas.scaleBy(x: -1, y: 1)
    }

    let rep = clip.repetition(at: frame)
    let depth = rep?.position(at: frame) ?? 0
    let skin = CGColor(red: 0.74, green: 0.48, blue: 0.32, alpha: 1)
    let shirt = CGColor(red: 0.18, green: 0.42, blue: 0.55, alpha: 1)
    let pants = CGColor(red: 0.19, green: 0.23, blue: 0.33, alpha: 1)
    let weight = CGColor(gray: 0.19, alpha: 1)

    switch rep?.exercise {
    case .pushUp:
        let hip = point(172, 108 - 32 * depth)
        let shoulder = point(278, 141 - 56 * depth)
        canvas.line([point(72, 70), hip], thickness: 22, color: pants)
        canvas.line([hip, shoulder], thickness: 31, color: shirt)
        canvas.line([shoulder, point(266 - 28 * depth, 110 - 18 * depth), point(285, 69)], thickness: 13, color: skin)
        canvas.head(point(311, 148 - 55 * depth), color: skin)
    case .squat:
        let hip = point(177 - 30 * depth, 173 - 59 * depth)
        let shoulder = point(190 + 23 * depth, 258 - 77 * depth)
        canvas.line([hip, point(183 + 28 * depth, 115 - 5 * depth), point(181, 76)], thickness: 25, color: pants)
        canvas.line([point(178, 74), point(202, 74)], thickness: 15, color: weight)
        canvas.line([hip, shoulder], thickness: 34, color: shirt)
        canvas.line([shoulder, point(225 + 20 * depth, shoulder.y - 14), point(266 + 15 * depth, shoulder.y - 16)], thickness: 13, color: skin)
        canvas.head(point(shoulder.x + 4, shoulder.y + 40), color: skin)
    default:
        let shoulder = point(187, 260)
        canvas.line([point(173, 74), point(184, 172), point(203, 74)], thickness: 23, color: pants)
        canvas.line([point(185, 174), shoulder], thickness: 35, color: shirt)
        canvas.head(point(189, 300), color: skin)
        if rep?.exercise == .overheadPress {
            let elbow = point(229 - 20 * depth, 230 + 65 * depth)
            let wrist = point(232 - 21 * depth, 273 + 68 * depth)
            canvas.line([shoulder, elbow, wrist], thickness: 13, color: skin)
            canvas.line([point(wrist.x - 13, wrist.y + 6), point(wrist.x + 13, wrist.y + 6)], thickness: 10, color: weight)
        } else {
            let elbow = point(209, 208)
            let angle = CGFloat(-.pi / 2 + 2.82 * Double(depth))
            let wrist = point(elbow.x + 48 * cos(angle), elbow.y + 48 * sin(angle))
            canvas.line([shoulder, elbow, wrist], thickness: 13, color: skin)
            if rep?.exercise == .curl {
                canvas.line([point(wrist.x - 12, wrist.y), point(wrist.x + 12, wrist.y)], thickness: 12, color: weight)
            }
        }
    }

    if clip.hidden?.contains(frame) == true {
        canvas.setFillColor(gray: 0.36, alpha: 1)
        canvas.fill(CGRect(x: 43, y: 67, width: 299, height: 286))
    }
}

/// The encoder queue owns the writer, its input, and the frame counter after startWriting.
private final class Encoder: @unchecked Sendable {
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

private func write(_ clip: Clip, to url: URL) async throws {
    let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: size, AVVideoHeightKey: size
    ])
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: size, kCVPixelBufferHeightKey as String: size,
        kCVPixelBufferCGImageCompatibilityKey as String: true,
        kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
    ])
    writer.add(input)
    guard writer.startWriting() else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
    writer.startSession(atSourceTime: .zero)
    let queue = DispatchQueue(label: "soma.video-timing-fixtures.encoder")
    let state = Encoder(writer: writer, input: input, adaptor: adaptor)
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
        input.requestMediaDataWhenReady(on: queue) {
            while state.input.isReadyForMoreMediaData {
                guard state.frame < clip.frames else {
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
                var buffer: CVPixelBuffer?
                guard let pool = state.adaptor.pixelBufferPool,
                      CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess,
                      let buffer
                else {
                    state.writer.cancelWriting()
                    continuation.resume(throwing: CocoaError(.fileWriteUnknown))
                    return
                }
                CVPixelBufferLockBaseAddress(buffer, [])
                let canvas = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: size, height: size, bitsPerComponent: 8,
                                       bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpaceCreateDeviceRGB(),
                                       bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue)
                if let canvas {
                    draw(clip, frame: state.frame, into: canvas)
                }
                CVPixelBufferUnlockBaseAddress(buffer, [])
                let timestamp = CMTime(value: Int64(state.frame), timescale: frameRate)
                guard canvas != nil, state.adaptor.append(buffer, withPresentationTime: timestamp) else {
                    state.writer.cancelWriting()
                    continuation.resume(throwing: state.writer.error ?? CocoaError(.fileWriteUnknown))
                    return
                }
                state.frame += 1
            }
        }
    }
}

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("Usage: xcrun swift scripts/build-video-timing-fixtures.swift NEW_OUTPUT_DIRECTORY\n".utf8))
    exit(2)
}

let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
guard !FileManager.default.fileExists(atPath: directory.path) else {
    throw CocoaError(.fileWriteFileExists)
}

try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
private var truth: [GroundTruth] = []
for (index, clip) in clips.enumerated() {
    let name = String(format: "clip-%02d.mp4", index + 1)
    try await write(clip, to: directory.appendingPathComponent(name))
    truth.append(GroundTruth(clip: clip, file: name))
}

let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
try encoder.encode(truth).write(to: directory.appendingPathComponent("ground-truth.json"), options: .atomic)
print("Wrote \(truth.count) synthetic clips and ground-truth.json")
