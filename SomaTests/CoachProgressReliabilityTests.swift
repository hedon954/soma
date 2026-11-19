@testable import Soma
import SwiftData
import UIKit
import XCTest

final class CoachProgressReliabilityTests: XCTestCase {
    func testDailyEnergyUsesLocalReadForStandaloneWordingVariants() {
        for question in [DeviceCoachRead.dailyEnergy.prompt, "我今天还有多少的卡路里额度？", "今天还剩多少大卡呢？", "我今天摄入和消耗了多少热量"] {
            XCTAssertEqual(DeviceCoachRead.matching(question), .dailyEnergy)
        }
        for request in ["记一下我吃了米饭，再看看今天还剩多少热量", "今天还剩多少热量？顺便帮我记一杯牛奶", "昨天还剩多少热量"] {
            XCTAssertNil(DeviceCoachRead.matching(request))
        }
    }

    func testCompletionSuggestionRequiresUsualExercisesAndActualSets() {
        let squat = UUID()
        let press = UUID()
        let unrelated = UUID()
        let usual = [squat: 3, press: 2]
        let history = Array(repeating: usual, count: 3)
        XCTAssertTrue(TrainingCompletionEvidence.matchesUsualSession(today: usual, history: history))
        XCTAssertFalse(TrainingCompletionEvidence.matchesUsualSession(today: usual, history: Array(history.prefix(2))))
        XCTAssertFalse(TrainingCompletionEvidence.matchesUsualSession(today: [squat: 2, press: 2], history: history))
        XCTAssertFalse(TrainingCompletionEvidence.matchesUsualSession(today: [squat: 3, unrelated: 2], history: history))
    }

    func testBackfillBindsTheSelectedDateAndMealBeforeLaterWords() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 19, hour: 12)))
        let target = try XCTUnwrap(MealBackfillTarget.parse(prompt: "帮我记录2026年11月17日的早餐：和午餐吃的一样", reference: now, calendar: calendar))
        XCTAssertEqual(target.meal, .breakfast)
        XCTAssertEqual(calendar.component(.day, from: target.day), 17)
        XCTAssertNil(MealBackfillTarget.parse(prompt: "帮我记录2026年11月31日的早餐：", reference: now, calendar: calendar))
    }

    func testOnlyMissingMainMealsBecomeDueAtEightAndOnPriorDays() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 19, hour: 20)))
        let today = calendar.startOfDay(for: now)
        let yesterday = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: today))
        let todayWithLunch = MealCoverage(recorded: [.lunch, .snack], skipped: [])
        XCTAssertEqual(todayWithLunch.missing.filter { MealCoverage.due($0, on: today, now: now, calendar: calendar) }, [.breakfast])
        let yesterdayEmpty = MealCoverage(recorded: [], skipped: [])
        XCTAssertEqual(yesterdayEmpty.missing.filter { MealCoverage.due($0, on: yesterday, now: now, calendar: calendar) }, [.breakfast, .lunch, .dinner])
        XCTAssertEqual(MealCoverage(recorded: [.breakfast, .lunch, .snack], skipped: []).missing, [.dinner])
        XCTAssertTrue(MealCoverage(recorded: [.breakfast, .lunch], skipped: [.dinner]).isComplete)
    }

    func testNutritionEvidenceKeepsKilojoulesAndServingBasis() {
        let evidence = NutritionLabelRecognition.summarize(["营养成分表", "每 100 g", "能量 418.4 kJ 100 kcal", "蛋白质 6.5 g"])
        XCTAssertTrue(evidence.contains("包装标有每 100 g"))
        XCTAssertTrue(evidence.contains("418.4 kJ（换算约 100 kcal）"))
        XCTAssertTrue(evidence.contains("100 kcal"))
        XCTAssertTrue(evidence.contains("蛋白质 6.5 g"))
        XCTAssertFalse(evidence.contains("418.4 kcal"))
        XCTAssertTrue(NutritionLabelRecognition.summarize(["器械负荷 100 kg"]).isEmpty)
        let twoColumns = NutritionLabelRecognition.summarize(["Nutrition Facts", "Per 100 g     Per serving", "Energy 1,255.2 kJ    418.4 kJ"])
        XCTAssertEqual(twoColumns, ["包装标有每 100 g", "包装标有每份", "1255.2 kJ（换算约 300 kcal）", "418.4 kJ（换算约 100 kcal）"])
        XCTAssertTrue(NutritionLabelRecognition.summarize(["营养成分表", "每１００克", "能量 418.4 kJ"]).contains("包装标有每 100 g"))
        XCTAssertTrue(NutritionLabelRecognition.summarize(["营养成分表", "每100毫升", "能量 209.2 kJ"]).contains("包装标有每 100 mL"))
    }

    @MainActor
    func testPhotoLabelsKeepNutritionEvidenceBoundToTheirOwnImage() async throws {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 720, height: 280))
        let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 40), .foregroundColor: UIColor.black]
        let images = [
            ["Nutrition Facts", "Per 100 g", "Energy 418.4 kJ", "Protein 6.5 g"],
            ["Nutrition Facts", "Per serving", "Energy 230 kcal", "Protein 14 g"]
        ].map { lines in
            renderer.pngData { output in
                UIColor.white.setFill()
                output.fill(CGRect(x: 0, y: 0, width: 720, height: 280))
                for (index, line) in lines.enumerated() {
                    (line as NSString).draw(at: CGPoint(x: 28, y: 14 + 57 * index), withAttributes: attributes)
                }
            }
        }
        let result = await NutritionLabelRecognition.context(for: images)
        let groups = try XCTUnwrap(result).split(separator: "\n")
        guard groups.count == 3 else {
            XCTFail("需要分别返回两张图片的营养标签证据：\(groups)")
            return
        }
        XCTAssertTrue(groups[1].contains("第 1 张：包装标有每 100 g；每 100 g 能量 418.4 kJ（换算约 100 kcal）"))
        XCTAssertTrue(groups[1].contains("蛋白质 6.5 g"))
        XCTAssertTrue(groups[2].contains("第 2 张：包装标有每份；每份 能量 230 kcal"))
        XCTAssertTrue(groups[2].contains("蛋白质 14 g"))

        let turnID = UUID()
        let history = AgentConversationExchange(turnID: turnID, userText: "历史图片", assistantText: nil,
                                                images: [images[1]], referencedImageOrdinal: 2,
                                                imageAttachmentCount: 2, videoAttachmentCount: 0)
        let correction = await NutritionLabelRecognition.context(for: [], history: [history])
        let scoped = try XCTUnwrap(correction)
        XCTAssertTrue(scoped.contains("历史 [TURN \(turnID.uuidString.lowercased())] 第 2 张：包装标有每份；每份 能量 230 kcal"), scoped)
        XCTAssertFalse(scoped.contains("第 1 张"), scoped)
    }

    @MainActor
    func testPhotoLabelUsesColumnPositionsAndFlagsConflictingEnergyUnits() async throws {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 960, height: 275))
        let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.monospacedSystemFont(ofSize: 25, weight: .medium)]
        let image = renderer.pngData { output in
            UIColor.white.setFill()
            output.fill(CGRect(x: 0, y: 0, width: 960, height: 275))
            for (left, top, text) in [
                (25, 12, "Nutrition Facts"), (300, 59, "Per 100 g"), (600, 59, "Per serving"),
                (25, 106, "Energy"), (300, 106, "418.4 kJ / 175 kcal"), (600, 106, "209.2 kJ / 50 kcal"),
                (25, 153, "Protein"), (300, 153, "6.5 g"),
                (25, 200, "Fat"), (300, 200, "3.2 g"), (600, 200, "1.6 g")
            ] {
                (text as NSString).draw(at: CGPoint(x: left, y: top), withAttributes: attributes)
            }
        }
        let result = await NutritionLabelRecognition.context(for: [image])
        let evidence = try XCTUnwrap(result)
        XCTAssertTrue(evidence.contains("每 100 g 能量 418.4 kJ（换算约 100 kcal） / 175 kcal（两单位不一致，需核对）"), evidence)
        XCTAssertTrue(evidence.contains("每份 能量 209.2 kJ（换算约 50 kcal） / 50 kcal"), evidence)
        XCTAssertTrue(evidence.contains("每 100 g 蛋白质 6.5 g"), evidence)
        XCTAssertFalse(evidence.contains("每份 蛋白质"), evidence)
        XCTAssertTrue(evidence.contains("每份 脂肪 1.6 g"), evidence)
    }

    @MainActor
    func testReflectedHeadingDoesNotMoveOtherColumnValuesIntoTheVisibleBasis() async throws {
        let size = CGSize(width: 960, height: 275)
        let renderer = UIGraphicsImageRenderer(size: size)
        let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.monospacedSystemFont(ofSize: 25, weight: .medium)]
        let reflectedLabel = renderer.jpegData(withCompressionQuality: 0.78) { output in
            UIColor(white: 0.9, alpha: 1).setFill()
            output.fill(CGRect(origin: .zero, size: size))
            for (left, top, text) in [
                (25, 12, "Nutrition Facts"), (300, 59, "Per 100 g"), (620, 59, "Per serving"),
                (25, 106, "Energy"), (300, 106, "418.4 kJ / 100 kcal"), (620, 106, "50 kcal"),
                (25, 153, "Protein"), (620, 153, "3.7 g"),
                (25, 200, "Fat"), (300, 200, "6.4 g"), (620, 200, "3.2 g")
            ] {
                (text as NSString).draw(at: CGPoint(x: left, y: top), withAttributes: attributes)
            }
            UIColor.white.setFill()
            output.fill(CGRect(x: 605, y: 57, width: 215, height: 32))
        }
        let result = await NutritionLabelRecognition.context(for: [reflectedLabel])
        let evidence = try XCTUnwrap(result)
        XCTAssertTrue(evidence.contains("每 100 g 能量 418.4 kJ（换算约 100 kcal） / 100 kcal"), evidence)
        XCTAssertTrue(evidence.contains("每 100 g 脂肪 6.4 g"), evidence)
        XCTAssertFalse(evidence.contains("50 kcal"), evidence)
        XCTAssertFalse(evidence.contains("3.7 g"), evidence)
        XCTAssertTrue(evidence.contains("部分数值无法对应列标题，请核对原图。"), evidence)
    }

    func testAnExplicitPhotoReferenceCanSelectAnArchivedTurn() {
        let older = ConversationContextProjection.Exchange(
            turnID: UUID(), userText: "样例包装", mediaAttachments: [.init(kind: .image, path: "fixture.jpg")]
        )
        let recent = ConversationContextProjection.Exchange(turnID: UUID(), userText: "继续", mediaAttachments: [])
        XCTAssertEqual(HistoricalMediaSelectionPolicy.selectedTurnIDs(
            currentText: "前面发的第二张图", hasCurrentMedia: false, exchanges: [recent], archived: [older]
        ), [older.turnID])
        XCTAssertEqual(HistoricalMediaSelectionPolicy.selectedTurnIDs(
            currentText: "把这张和刚才的照片对比一下", hasCurrentMedia: true, exchanges: [recent], archived: [older]
        ), [older.turnID])
        XCTAssertTrue(HistoricalMediaSelectionPolicy.selectedTurnIDs(
            currentText: "解释这个动作", hasCurrentMedia: false, exchanges: [recent], archived: [older]
        ).isEmpty)
    }

    func testRevisionRetainsOnlyTheSameVisibleRangeAndTimeZone() {
        let day = ProgressPeriod.day.window(containing: Date(timeIntervalSince1970: 100_000))
        let key = ProgressHistoryRequest(window: day, revision: 1, timeZoneID: "UTC")
        XCTAssertTrue(key.canDisplay(ProgressHistoryRequest(window: day, revision: 9, timeZoneID: "UTC")))
        XCTAssertFalse(key.canDisplay(ProgressHistoryRequest(window: day.shifted(by: 1), revision: 1, timeZoneID: "UTC")))
        XCTAssertFalse(key.canDisplay(ProgressHistoryRequest(window: day, revision: 1, timeZoneID: "Asia/Shanghai")))
    }

    @MainActor
    func testAdjacentManualEditsKeepOneReplyAndLatestValuesInAgentContext() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "test.soma.receipts.\(UUID())"))
        let spaces = DataSpaceController(defaults: defaults, isStoredInMemoryOnly: true)
        let context = spaces.personalContainer.mainContext
        let start = Date(timeIntervalSince1970: 100_000)
        let session = ConversationSession(startedAt: start)
        context.insert(session)
        try context.save()

        for (value, second) in [(20, 1.0), (10, 2.0)] {
            try RecordCorrectionReceipt.record("训练记录 #1 已改为 \(value) kg", sessionID: session.id,
                                               recordDate: start, in: context, now: start.addingTimeInterval(second))
            try context.save()
        }
        let turn = UUID()
        context.insert(CoachMessage(date: start.addingTimeInterval(3), sessionID: session.id,
                                    isFromCoach: false, text: "接着练", turnID: turn))
        try context.save()
        try RecordCorrectionReceipt.record("训练记录 #2 已改为 12 kg", sessionID: session.id,
                                           recordDate: start, in: context, now: start.addingTimeInterval(4))
        try context.save()

        let messages = try context.fetch(FetchDescriptor<CoachMessage>())
        XCTAssertEqual(messages.filter(\.isFromCoach).count, 2)
        let beforeTurn = ConversationContextProjection.make(messages: messages, sessionID: session.id, excludingTurnID: turn)
        XCTAssertEqual(beforeTurn.exchanges.map(\.assistantText), ["- 训练记录 #1 已改为 10 kg"])
        let history = ConversationContextProjection.make(messages: messages, sessionID: session.id, excludingTurnID: nil)
        XCTAssertTrue(history.exchanges.last?.assistantText?.contains("#2 已改为 12 kg") == true)
        let cardReply = CoachMessage(date: start, sessionID: session.id, isFromCoach: true, text: "已记录。", turnID: UUID())
        let firstReceipt = try XCTUnwrap(messages.first { $0.isManualCorrectionReceipt })
        XCTAssertEqual(ChatRecordEditPolicy.latestEditableAssistantMessageID(in: [cardReply, firstReceipt]), cardReply.id)
    }

    @MainActor
    func testConcurrentDeliveryRequestsSendConfirmedReportOnce() async throws {
        let name = "test.soma.delivery.\(UUID())"
        let folder = FileManager.default.temporaryDirectory.appending(path: name)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer {
            try? FileManager.default.removeItem(at: folder)
            defaults.removePersistentDomain(forName: name)
        }
        let reports = DiagnosticReportStore(directory: folder)
        var report = DiagnosticReport(subject: "合成诊断", body: "合成报告", evidenceSource: .metricKit)
        report.eventKey = "synthetic-crash-event"
        reports.save(report)
        let transport = CountingDiagnosticTransport()
        let coordinator = CrashDiagnosticsCoordinator(defaults: defaults, reports: reports, mailer: .init(
            credentialsProvider: { .init(senderAddress: "test@example.invalid", smtpAuthorizationCode: "test") },
            transport: transport
        ))
        async let first: Void = coordinator.deliverPendingReports()
        async let second: Void = coordinator.deliverPendingReports()
        _ = await (first, second)
        let count = await transport.count
        XCTAssertEqual(count, 1)
        XCTAssertTrue(reports.pendingReports().isEmpty)

        // 模拟退出发生在回执保存后、待发文件清理前。
        reports.save(report)
        let restarted = CrashDiagnosticsCoordinator(defaults: defaults, reports: reports, mailer: .init(
            credentialsProvider: { .init(senderAddress: "test@example.invalid", smtpAuthorizationCode: "test") },
            transport: transport
        ))
        await restarted.deliverPendingReports()
        let countAfterRestart = await transport.count
        XCTAssertEqual(countAfterRestart, 1)
        XCTAssertTrue(reports.pendingReports().isEmpty)
    }
}

private actor CountingDiagnosticTransport: FeedbackSMTPTransport {
    var count = 0
    func send(message _: Data, sender _: String, recipient _: String, authorizationCode _: String) async throws {
        count += 1
        await Task.yield()
    }
}
