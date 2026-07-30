@testable import Soma
import XCTest

final class WeatherContextProviderTests: XCTestCase {
    func testRequestUsesRoundedCoordinatesAndMinimumCurrentFields() throws {
        let url = try XCTUnwrap(OpenMeteoWeatherClient.requestURL(
            latitude: 31.2345,
            longitude: 121.4768
        ))
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let items = try Dictionary(uniqueKeysWithValues: XCTUnwrap(components.queryItems).map {
            ($0.name, $0.value ?? "")
        })

        XCTAssertEqual(components.scheme, "https")
        XCTAssertEqual(components.host, "api.open-meteo.com")
        XCTAssertEqual(components.path, "/v1/forecast")
        XCTAssertEqual(items["latitude"], "31.23")
        XCTAssertEqual(items["longitude"], "121.48")
        XCTAssertEqual(
            items["current"],
            "apparent_temperature,relative_humidity_2m,precipitation,uv_index"
        )
        XCTAssertEqual(items["temperature_unit"], "celsius")
        XCTAssertEqual(items["precipitation_unit"], "mm")
        XCTAssertEqual(items["forecast_days"], "1")
        XCTAssertNil(OpenMeteoWeatherClient.requestURL(
            latitude: 91,
            longitude: 121.47
        ))
    }

    func testResponseDecodesOnlyCurrentWeatherMeasurements() throws {
        let data = Data(
            """
            {
              "latitude": 31.23,
              "longitude": 121.48,
              "current": {
                "time": "2026-07-30T19:00",
                "apparent_temperature": 33.4,
                "relative_humidity_2m": 78,
                "precipitation": 0.2,
                "uv_index": 8.1
              }
            }
            """.utf8
        )

        let weather = try OpenMeteoWeatherClient.decode(data)

        XCTAssertEqual(weather.apparentTemperatureCelsius, 33.4)
        XCTAssertEqual(weather.relativeHumidityPercent, 78)
        XCTAssertEqual(weather.precipitationMillimeters, 0.2)
        XCTAssertEqual(weather.uvIndex, 8.1)
    }

    func testResponseWithoutCurrentMeasurementsFailsClosed() {
        let data = Data(#"{"current":{"time":"2026-07-30T19:00"}}"#.utf8)

        XCTAssertThrowsError(try OpenMeteoWeatherClient.decode(data)) { error in
            guard case OpenMeteoWeatherError.missingCurrentWeather = error else {
                return XCTFail("Expected missingCurrentWeather, got \(error)")
            }
        }
    }

    func testGuidanceDerivesRisksWithoutExposingRawWeatherValues() throws {
        let guidance = try XCTUnwrap(WeatherContextProvider.guidance(
            for: CurrentWeatherContext(
                apparentTemperatureCelsius: 29,
                relativeHumidityPercent: 80,
                precipitationMillimeters: 0.4,
                uvIndex: 9
            )
        ))

        XCTAssertTrue(guidance.contains("高温或高湿负担"))
        XCTAssertTrue(guidance.contains("紫外线风险较高"))
        XCTAssertTrue(guidance.contains("存在降水"))
        XCTAssertFalse(guidance.contains("29"))
        XCTAssertFalse(guidance.contains("80"))
        XCTAssertFalse(guidance.contains("0.4"))
    }

    func testGuidanceDoesNotInventMissingWeatherMeasurements() throws {
        let guidance = try XCTUnwrap(WeatherContextProvider.guidance(
            for: CurrentWeatherContext(
                apparentTemperatureCelsius: nil,
                relativeHumidityPercent: 60,
                precipitationMillimeters: nil,
                uvIndex: nil
            )
        ))

        XCTAssertTrue(guidance.contains("当前可用天气信号"))
        XCTAssertFalse(guidance.contains("高温或高湿负担"))
        XCTAssertNil(WeatherContextProvider.guidance(
            for: CurrentWeatherContext(
                apparentTemperatureCelsius: nil,
                relativeHumidityPercent: nil,
                precipitationMillimeters: nil,
                uvIndex: nil
            )
        ))
    }

    func testIrrelevantTextDoesNotLoadWeather() async {
        let loader = WeatherClientSpy(outcome: .success(CurrentWeatherContext(
            apparentTemperatureCelsius: 30,
            relativeHumidityPercent: 80,
            precipitationMillimeters: 0,
            uvIndex: 2
        )))
        let snapshot = makeSnapshot()

        let guidance = await WeatherContextProvider.transientGuidance(
            for: snapshot,
            text: "午餐吃了荞麦面",
            loader: loader
        )

        XCTAssertNil(guidance)
        let callCount = await loader.callCount()
        XCTAssertEqual(callCount, 0)
    }

    func testWeatherFailureDoesNotProduceContext() async {
        let loader = WeatherClientSpy(outcome: .failure)

        let guidance = await WeatherContextProvider.transientGuidance(
            for: makeSnapshot(),
            text: "今晚适合户外跑步吗？",
            loader: loader
        )

        XCTAssertNil(guidance)
        let callCount = await loader.callCount()
        XCTAssertEqual(callCount, 1)
    }

    private func makeSnapshot() -> LocationSnapshot {
        LocationSnapshot(
            latitude: 31.2345,
            longitude: 121.4768,
            horizontalAccuracy: 30,
            capturedAt: .now,
            placeName: "测试地点"
        )
    }
}

private actor WeatherClientSpy: CurrentWeatherLoading {
    enum Outcome: Sendable {
        case success(CurrentWeatherContext)
        case failure
    }

    private let outcome: Outcome
    private var calls = 0

    init(outcome: Outcome) {
        self.outcome = outcome
    }

    func currentWeather(
        latitude: Double,
        longitude: Double
    ) async throws -> CurrentWeatherContext {
        calls += 1
        switch outcome {
        case let .success(weather):
            return weather
        case .failure:
            throw WeatherClientSpyError.unavailable
        }
    }

    func callCount() -> Int {
        calls
    }
}

private enum WeatherClientSpyError: Error {
    case unavailable
}
