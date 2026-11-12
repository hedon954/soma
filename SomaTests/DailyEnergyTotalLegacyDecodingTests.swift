@testable import Soma
import SwiftData
import XCTest

private struct DailyEnergyTotalLegacyFixtureComponents: Codable {
    enum Activity: Codable {
        case selected(Double)
        case disaggregated(training: Double, remaining: Double)
        case recordedTraining(Double)
        case absent
    }

    var restingKilocalories: Double
    var coefficient: Double
    var activity: Activity
}

final class DailyEnergyTotalLegacyDecodingTests: XCTestCase {
    func testEnergyInputCodingPayloadsFromOldActivityCasesStillDecode() throws {
        let recordedJSON = try String(data: EnergyInputCoding.encode(
            DailyEnergyTotalLegacyFixtureComponents(restingKilocalories: 1600, coefficient: 1.4, activity: .recordedTraining(320))
        ), encoding: .utf8)
        XCTAssertTrue(recordedJSON?.contains(#""recordedTraining":{"_0":"#) == true, recordedJSON ?? "")

        let recorded = try decode(.init(restingKilocalories: 1600, coefficient: 1.4, activity: .recordedTraining(320)))
        XCTAssertEqual(recorded.activity, .absent)
        XCTAssertEqual(recorded.trainingKilocalories, 320)
        XCTAssertEqual(recorded.totalKilocalories, 1600 * 1.4 + 320, accuracy: 0.001)

        let split = try decode(
            .init(restingKilocalories: 1600, coefficient: 1.4, activity: .disaggregated(training: 120, remaining: 330))
        )
        XCTAssertEqual(split.activity, .selected(450))
        XCTAssertEqual(split.trainingKilocalories, 0)
        XCTAssertEqual(split.totalKilocalories, 1600 * 1.4 + 450, accuracy: 0.001)

        let selected = try decode(.init(restingKilocalories: 1600, coefficient: 1.4, activity: .selected(250)))
        XCTAssertEqual(selected.activity, .selected(250))
        XCTAssertEqual(selected.trainingKilocalories, 0)

        let absent = try decode(.init(restingKilocalories: 1600, coefficient: 1.4, activity: .absent))
        XCTAssertEqual(absent.activity, .absent)
        XCTAssertEqual(absent.trainingKilocalories, 0)
    }

    func testPlainDoubleUnkeyedAndAnonymousDictionaryEncodingsAllDecode() throws {
        let recorded = try decodeJSON(
            #"{"restingKilocalories":1600,"coefficient":1.4,"activity":{"recordedTraining":320}}"#
        )
        XCTAssertEqual(recorded.activity, .absent)
        XCTAssertEqual(recorded.trainingKilocalories, 320)

        let unkeyed = try decodeJSON(
            #"{"restingKilocalories":1600,"coefficient":1.4,"activity":{"recordedTraining":[280]}}"#
        )
        XCTAssertEqual(unkeyed.activity, .absent)
        XCTAssertEqual(unkeyed.trainingKilocalories, 280)

        let splitUnkeyed = try decodeJSON(
            #"{"restingKilocalories":1600,"coefficient":1.4,"activity":{"disaggregated":[120,330]}}"#
        )
        XCTAssertEqual(splitUnkeyed.activity, .selected(450))
        XCTAssertEqual(splitUnkeyed.trainingKilocalories, 0)

        let splitAnonymous = try decodeJSON(
            #"{"restingKilocalories":1600,"coefficient":1.4,"activity":{"disaggregated":{"_0":120,"_1":330}}}"#
        )
        XCTAssertEqual(splitAnonymous.activity, .selected(450))
    }

    func testCurrentComponentsRoundTripThroughEnergyInputCoding() throws {
        let original = DailyEnergyTotal.Components(
            restingKilocalories: 1600, coefficient: 1.4, activity: .selected(250), trainingKilocalories: 80
        )
        let data = try EnergyInputCoding.encode(original)
        let json = String(data: data, encoding: .utf8)
        XCTAssertTrue(json?.contains(#""selected":{"_0":"#) == true, json ?? "")
        XCTAssertEqual(try JSONDecoder().decode(DailyEnergyTotal.Components.self, from: data), original)

        let absent = DailyEnergyTotal.Components(
            restingKilocalories: 1600, coefficient: 1.4, activity: .absent, trainingKilocalories: 0
        )
        XCTAssertEqual(
            try JSONDecoder().decode(DailyEnergyTotal.Components.self, from: EnergyInputCoding.encode(absent)),
            absent
        )
    }

    func testInvalidBoundaryTrainingValuesStillDecodeWithoutThrowing() throws {
        let negative = try decodeJSON(
            #"{"restingKilocalories":1600,"coefficient":1.4,"activity":{"recordedTraining":{"_0":-8}}}"#
        )
        XCTAssertEqual(negative.activity, .absent)
        XCTAssertEqual(negative.trainingKilocalories, -8)

        let tooLarge = try decodeJSON(
            #"{"restingKilocalories":1600,"coefficient":1.4,"activity":{"recordedTraining":{"_0":100000}}}"#
        )
        XCTAssertEqual(tooLarge.trainingKilocalories, 100_000)
    }

    func testOldCalibrationReviewWithPresentedTotalStillDecodesForProgressLoad() throws {
        let day = Date(timeIntervalSince1970: 1_790_000_000)
        let calculation = calculation(on: day)
        let presented = DailyEnergyTotalLegacyFixtureComponents(restingKilocalories: 1600, coefficient: 1.4, activity: .recordedTraining(320))
        let calculationData = try splicePresentedTotal(EnergyInputCoding.encode(calculation), presented: presented)
        let decodedCalculation = try JSONDecoder().decode(EnergyDayCalculation.self, from: calculationData)
        XCTAssertEqual(decodedCalculation.presentedTotal?.activity, .absent)
        XCTAssertEqual(decodedCalculation.presentedTotal?.trainingKilocalories, 320)

        let review = EnergyCalibrationReview(
            date: day, windowStart: day, windowEnd: day, inputFingerprint: "fixture",
            previousCorrection: 0, nextCorrection: 0, meanIntake: nil, meanModel: nil,
            slope: nil, minimumCandidate: nil, maximumCandidate: nil, weightDayCount: 0,
            direction: 0, evidenceEligible: false, reason: "虚构校准",
            inputDays: [
                .init(
                    date: day, intake: 2000, uncalibratedTotal: 2240, foodComplete: true,
                    activityComplete: true, weights: [70], fluidChangeConcern: false,
                    calculation: decodedCalculation, sourceMealIDs: nil
                )
            ]
        )
        let reviewData = try spliceReviewPresentedTotal(EnergyInputCoding.encode(review), presented: presented)
        let decodedReview = try JSONDecoder().decode(EnergyCalibrationReview.self, from: reviewData)
        XCTAssertEqual(decodedReview.inputDays?.first?.calculation?.presentedTotal?.trainingKilocalories, 320)
        XCTAssertEqual(decodedReview.inputDays?.first?.calculation?.presentedTotal?.activity, .absent)
    }

    @MainActor
    func testProgressHistoryLoaderReadsLegacyPresentedTotalReview() async throws {
        let calendar = Calendar(identifier: .gregorian)
        let day = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_790_000_000))
        let container = try ModelContainer(
            for: Schema(SomaDataSchema.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        context.insert(UserProfile())
        let presented = DailyEnergyTotalLegacyFixtureComponents(restingKilocalories: 1600, coefficient: 1.4, activity: .recordedTraining(320))
        let review = EnergyCalibrationReview(
            date: day, windowStart: day, windowEnd: day, inputFingerprint: "fixture",
            previousCorrection: 0, nextCorrection: 0, meanIntake: nil, meanModel: nil,
            slope: nil, minimumCandidate: nil, maximumCandidate: nil, weightDayCount: 0,
            direction: 0, evidenceEligible: false, reason: "虚构校准",
            inputDays: [
                .init(
                    date: day, intake: 2000, uncalibratedTotal: 2240, foodComplete: true,
                    activityComplete: true, weights: [70], fluidChangeConcern: false,
                    calculation: calculation(on: day), sourceMealIDs: nil
                )
            ]
        )
        let payload = try spliceReviewPresentedTotal(EnergyInputCoding.encode(review), presented: presented)
        context.insert(
            EnergyEvidenceEntry(
                key: "calibration:legacy-fixture", kindRaw: EnergyEvidenceKind.calibration.rawValue,
                date: day, payload: payload, reason: "虚构旧格式", predecessorKey: nil
            )
        )
        try context.save()

        let loader = ProgressHistoryLoader(modelContainer: container)
        let window = ProgressPeriod.day.window(containing: day, calendar: calendar)
        let facts = try await loader.load(window: window)
        XCTAssertNotNil(facts.profile)
        XCTAssertEqual(
            facts.profile?.energyFacts.reviews.first?.inputDays?.first?.calculation?.presentedTotal?
                .trainingKilocalories,
            320
        )
    }

    private func decode(_ old: DailyEnergyTotalLegacyFixtureComponents) throws -> DailyEnergyTotal.Components {
        try JSONDecoder().decode(DailyEnergyTotal.Components.self, from: EnergyInputCoding.encode(old))
    }

    private func decodeJSON(_ json: String) throws -> DailyEnergyTotal.Components {
        try JSONDecoder().decode(DailyEnergyTotal.Components.self, from: Data(json.utf8))
    }

    private func calculation(on day: Date) -> EnergyDayCalculation {
        let reference = EnergyReferenceDay(effectiveFrom: day, factor: 1.4, reason: "虚构参考")
        let input = EnergyDayInput(
            date: day, resting: 1600, weightKG: 70, reference: reference,
            nonTrainingKilometers: nil, walkingCoverageConfirmed: false, isEndedDay: true,
            training: [], correction: 0
        )
        return EnergyDayCalculation(
            input: input, baseline: 2240, walkingDelta: 0, trainingDelta: 0,
            displacedActivityPerHour: 0, adoptedTrainingIDs: [], excludedTrainingIDs: [], issues: []
        )
    }

    private func splicePresentedTotal(_ data: Data, presented: DailyEnergyTotalLegacyFixtureComponents) throws -> Data {
        var object = try jsonObject(data)
        object["presentedTotal"] = try jsonObject(EnergyInputCoding.encode(presented))
        return try JSONSerialization.data(withJSONObject: object)
    }

    private func spliceReviewPresentedTotal(_ data: Data, presented: DailyEnergyTotalLegacyFixtureComponents) throws -> Data {
        var object = try jsonObject(data)
        guard var days = object["inputDays"] as? [[String: Any]], var first = days.first else {
            return data
        }
        var calc = first["calculation"] as? [String: Any] ?? [:]
        calc["presentedTotal"] = try jsonObject(EnergyInputCoding.encode(presented))
        first["calculation"] = calc
        days[0] = first
        object["inputDays"] = days
        return try JSONSerialization.data(withJSONObject: object)
    }

    private func jsonObject(_ data: Data) throws -> [String: Any] {
        let value = try JSONSerialization.jsonObject(with: data)
        guard let object = value as? [String: Any] else {
            throw NSError(domain: "DailyEnergyTotalLegacyDecodingTests", code: 1)
        }
        return object
    }
}
