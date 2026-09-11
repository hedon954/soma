@testable import Soma
import SwiftOpenAI
import XCTest

@MainActor
final class AppErrorMessageTests: XCTestCase {
    func testModelErrorsExplainCauseAndNextStepWithoutProviderPayload() {
        let service = AIService(apiKeyOverride: "fixture")
        let raw = "{\"error\":{\"message\":\"unknown variant video_url, expected text,image_url,file\",\"request_id\":\"fixture-secret-id\"}}"
        let text = service.agentErrorDescription(APIError.responseUnsuccessful(description: raw, statusCode: 400))
        XCTAssertFalse(text.contains("video_url"))
        XCTAssertFalse(text.contains("request_id"))
        XCTAssertFalse(text.contains("fixture-secret-id"))
        XCTAssertFalse(text.contains("{"))
        XCTAssertTrue(text.contains("视频"))
        XCTAssertTrue(text.contains("模型") && (text.contains("更换") || text.contains("切换")))
    }

    func testModelAuthQuotaAndNetworkFailuresGiveDifferentRecovery() {
        let service = AIService(apiKeyOverride: "fixture")
        let auth = service.agentErrorDescription(APIError.responseUnsuccessful(description: "invalid_api_key", statusCode: 401))
        let quota = service.agentErrorDescription(APIError.responseUnsuccessful(description: "insufficient_quota", statusCode: 429))
        let network = service.agentErrorDescription(URLError(.notConnectedToInternet))
        XCTAssertTrue(auth.contains("设置"))
        XCTAssertTrue(quota.contains("额度") || quota.contains("余额"))
        XCTAssertTrue(network.contains("网络"))
        XCTAssertFalse(auth.contains("invalid_api_key"))
        XCTAssertFalse(quota.contains("insufficient_quota"))
    }

    func testLocalFileAndPermissionErrorsHaveConcreteRecovery() {
        let disk = AppErrorMessage.message(for: CocoaError(.fileWriteOutOfSpace), operation: .save)
        let missing = AppErrorMessage.message(for: CocoaError(.fileReadNoSuchFile), operation: .media)
        let permission = AppErrorMessage.message(for: CocoaError(.fileReadNoPermission), operation: .backup)
        XCTAssertTrue(disk.contains("存储空间") && disk.contains("释放"))
        XCTAssertTrue(missing.contains("重新选择"))
        XCTAssertTrue(permission.contains("权限") && permission.contains("重新选择"))
        let microphone = AppErrorMessage.message(for: SpeechInputError.microphonePermissionDenied, operation: .speech)
        XCTAssertTrue(microphone.contains("系统设置") && microphone.contains("麦克风"))
        let wrapped = NSError(domain: "FictionalStore", code: 1,
                              userInfo: [NSUnderlyingErrorKey: CocoaError(.fileWriteOutOfSpace)])
        XCTAssertTrue(AppErrorMessage.message(for: wrapped, operation: .save).contains("存储空间"))
    }

    func testUnknownAndPersistedErrorsNeverInventACauseOrExposeInternalIDs() {
        let unknown = NSError(domain: "PrivateFixtureDomain", code: 918,
                              userInfo: [NSLocalizedDescriptionKey: "opaque internal failure"])
        let result = AppErrorMessage.message(for: unknown, operation: .save)
        XCTAssertTrue(result.contains("无法确定具体原因"))
        XCTAssertFalse(result.contains("PrivateFixtureDomain"))
        XCTAssertFalse(result.contains("918"))
        XCTAssertFalse(result.contains("空间不足"))
        let id = UUID()
        let missing = AppErrorMessage.message(for: TrainingPlanError.missingExercise(id), operation: .save)
        XCTAssertFalse(missing.contains(id.uuidString))
        XCTAssertTrue(missing.contains("替换"))
        let legacy = AppErrorMessage.message(from: "写入失败 request_id=private_value", operation: .save)
        XCTAssertFalse(legacy.contains("private_value"))
        XCTAssertEqual(AppErrorMessage.message(from: "重量必须大于零，请修改后保存。"), "重量必须大于零，请修改后保存。")
        XCTAssertTrue(AppErrorMessage.message(from: "模型请求失败").contains("重试"))
    }

    func testRecoveryAndDiagnosticsAreSeparatedFromOrdinaryRecordingError() {
        let diagnosis = WorkoutRecordingFailureDiagnosis(cause: "摄像头被其他 App 占用",
                                                         technical: "AVFoundationErrorDomain -11818 · fixture")
        XCTAssertFalse(diagnosis.failureMessage.contains("AVFoundation"))
        XCTAssertFalse(diagnosis.partialRecordingMessage.contains("11818"))
        XCTAssertTrue(diagnosis.partialRecordingMessage.contains("保留可用的部分视频"))
        XCTAssertTrue(diagnosis.failureMessage.contains("重试"))
        XCTAssertTrue(diagnosis.technical.contains("11818"))
        let migration = DataMigrationError.invalidTrainingSnapshot("fixture", UUID())
        let text = AppErrorMessage.message(for: migration, operation: .startup)
        XCTAssertTrue(text.contains("保护原数据"))
        XCTAssertTrue(text.contains("导出诊断"))
        XCTAssertFalse(text.contains("fixture"))
    }

    func testRemoteFailureCodesAndFeedbackConfigurationHaveUserActions() {
        for code in ["provider_authentication_failed", "provider_quota_exhausted",
                     "provider_rate_limited", "provider_context_exceeded", "video_fallback_unavailable",
                     "provider_configuration_invalid", "upload_incomplete", "protocol_unsupported"]
        {
            let message = AppErrorMessage.message(for: RemoteAgentError.server(code: code, message: "raw-private-payload"))
            XCTAssertTrue(message.contains("请"))
            XCTAssertFalse(message.contains(code))
            XCTAssertFalse(message.contains("raw-private-payload"))
            XCTAssertFalse(message.contains("关闭远程"))
            XCTAssertFalse(message.contains("重新连接远程"))
        }
        let feedback = AppErrorMessage.message(for: FeedbackSubmissionError.configurationMissing, operation: .feedback)
        XCTAssertFalse(feedback.contains("plist"))
        XCTAssertTrue(feedback.contains("更新"))
        let configuration = AppErrorMessage.message(for: AIExtraConfigError.notObject, operation: .configuration)
        XCTAssertTrue(configuration.contains("清空"))
        XCTAssertFalse(configuration.contains("{"))
    }
}
