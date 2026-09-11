import AVFoundation
@testable import Soma
import XCTest

/// BUG 0025：录像失败必须给出具体原因和可检索的技术标识。
final class WorkoutRecordingFailureDiagnosisTests: XCTestCase {
    func testDiskFullMapsToStorageCause() {
        let diagnosis = WorkoutRecordingFailureDiagnosis.make(
            error: avError(.diskFull),
            stage: "finish-unexpected"
        )

        XCTAssertEqual(diagnosis.cause, "设备存储空间不足，无法继续写入视频")
        XCTAssertTrue(diagnosis.technical.contains(AVFoundationErrorDomain))
        XCTAssertTrue(
            diagnosis.technical.contains("\(AVError.Code.diskFull.rawValue)")
        )
        XCTAssertTrue(diagnosis.technical.hasSuffix("finish-unexpected"))
    }

    func testSessionInterruptedMapsToInterruptionCause() {
        let diagnosis = WorkoutRecordingFailureDiagnosis.make(
            error: avError(.sessionWasInterrupted),
            stage: "finish-unexpected"
        )

        XCTAssertEqual(
            diagnosis.cause,
            "相机会话被系统中断（来电、其它 App 抢占相机或分屏）"
        )
    }

    func testSessionConfigurationChangedIsCalledOutSeparately() {
        let diagnosis = WorkoutRecordingFailureDiagnosis.make(
            error: avError(.sessionConfigurationChanged),
            stage: "finish-unexpected"
        )

        XCTAssertEqual(
            diagnosis.cause,
            "录像过程中相机配置被改动（预览或方向重建）"
        )
    }

    func testMediaServicesResetAndDeviceLossAreDistinct() {
        let reset = WorkoutRecordingFailureDiagnosis.make(
            error: avError(.mediaServicesWereReset),
            stage: "runtime"
        )
        let disconnected = WorkoutRecordingFailureDiagnosis.make(
            error: avError(.deviceWasDisconnected),
            stage: "runtime"
        )

        XCTAssertEqual(reset.cause, "系统媒体服务被重置，相机需要重新启动")
        XCTAssertEqual(disconnected.cause, "摄像头在录像过程中断开")
        XCTAssertNotEqual(reset.technical, disconnected.technical)
    }

    func testMissingErrorStillExplainsWhatIsKnown() {
        let diagnosis = WorkoutRecordingFailureDiagnosis.make(
            error: nil,
            stage: "finish-unexpected"
        )

        XCTAssertEqual(diagnosis.cause, WorkoutRecordingFailureDiagnosis.unknownCause)
        XCTAssertEqual(diagnosis.technical, "no_error · finish-unexpected")
    }

    func testNonAVFoundationErrorExplainsStorageAndKeepsDiagnosticDomain() {
        let error = NSError(
            domain: NSPOSIXErrorDomain,
            code: 28,
            userInfo: [NSLocalizedDescriptionKey: "No space left on device"]
        )
        let diagnosis = WorkoutRecordingFailureDiagnosis.make(
            error: error,
            stage: "persist"
        )

        XCTAssertTrue(diagnosis.cause.contains("存储空间不足"))
        XCTAssertFalse(diagnosis.failureMessage.contains("No space left"))
        XCTAssertTrue(diagnosis.technical.contains(NSPOSIXErrorDomain))
        XCTAssertTrue(diagnosis.technical.contains("28"))
    }

    func testUnderlyingErrorAndSuccessKeyEnterTechnicalDetail() {
        let underlying = NSError(domain: "OSStatus", code: -12780)
        let error = NSError(
            domain: AVFoundationErrorDomain,
            code: AVError.Code.unknown.rawValue,
            userInfo: [
                AVErrorRecordingSuccessfullyFinishedKey: true,
                NSUnderlyingErrorKey: underlying
            ]
        )
        let diagnosis = WorkoutRecordingFailureDiagnosis.make(
            error: error,
            stage: "finish-unexpected"
        )

        XCTAssertTrue(diagnosis.technical.contains("finished=true"))
        XCTAssertTrue(diagnosis.technical.contains("under=OSStatus -12780"))
    }

    func testEveryInterruptionReasonHasDistinctChineseCause() {
        let reasons: [AVCaptureSession.InterruptionReason] = [
            .videoDeviceNotAvailableInBackground,
            .audioDeviceInUseByAnotherClient,
            .videoDeviceInUseByAnotherClient,
            .videoDeviceNotAvailableWithMultipleForegroundApps,
            .videoDeviceNotAvailableDueToSystemPressure
        ]
        let causes = reasons.map(WorkoutRecordingFailureDiagnosis.cause(for:))

        XCTAssertEqual(Set(causes).count, reasons.count)
        XCTAssertFalse(causes.contains { $0.isEmpty })
    }

    func testInterruptionDiagnosisCarriesReasonCode() {
        let diagnosis = WorkoutRecordingFailureDiagnosis.interruption(
            reasonCode: AVCaptureSession.InterruptionReason
                .videoDeviceInUseByAnotherClient.rawValue,
            stage: "session-interruption"
        )

        XCTAssertEqual(diagnosis.cause, "摄像头被其它 App 占用")
        XCTAssertTrue(diagnosis.technical.contains("interruption_reason="))
        XCTAssertTrue(diagnosis.technical.hasSuffix("session-interruption"))
    }

    func testFutureInterruptionReasonKeepsRawValueOnlyInDiagnostics() {
        let diagnosis = WorkoutRecordingFailureDiagnosis.interruption(
            reasonCode: 9999,
            stage: "session-interruption"
        )

        XCTAssertEqual(diagnosis.cause, "相机被系统中断，未给出可确认的原因")
        XCTAssertFalse(diagnosis.failureMessage.contains("9999"))
        XCTAssertTrue(diagnosis.technical.contains("9999"))
    }

    func testMissingInterruptionReasonSaysSo() {
        let diagnosis = WorkoutRecordingFailureDiagnosis.interruption(
            reasonCode: nil,
            stage: "session-interruption"
        )

        XCTAssertEqual(diagnosis.cause, "相机被系统中断，未给出中断原因")
        XCTAssertTrue(diagnosis.technical.contains("interruption_reason=none"))
    }

    func testPartialAndFailureMessagesDifferWithoutTechnicalSuffix() {
        let diagnosis = WorkoutRecordingFailureDiagnosis(
            cause: "摄像头被其它 App 占用",
            technical: "AVFoundationErrorDomain -11818 · finish"
        )

        XCTAssertEqual(
            diagnosis.partialRecordingMessage,
            "摄像头被其它 App 占用；已保留可用的部分视频，训练数据不受影响。请检查相机与存储空间后重试。"
        )
        XCTAssertEqual(
            diagnosis.failureMessage,
            "摄像头被其它 App 占用；训练数据不受影响。请检查相机与存储空间后重试。"
        )
    }

    private func avError(_ code: AVError.Code) -> NSError {
        NSError(domain: AVFoundationErrorDomain, code: code.rawValue)
    }
}
