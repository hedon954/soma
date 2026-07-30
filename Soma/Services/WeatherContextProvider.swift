import Foundation

struct CurrentWeatherContext: Equatable, Sendable {
    var apparentTemperatureCelsius: Double?
    var relativeHumidityPercent: Double?
    var precipitationMillimeters: Double?
    var uvIndex: Double?

    var hasAnyMeasurement: Bool {
        apparentTemperatureCelsius != nil
            || relativeHumidityPercent != nil
            || precipitationMillimeters != nil
            || uvIndex != nil
    }
}

protocol CurrentWeatherLoading: Sendable {
    func currentWeather(
        latitude: Double,
        longitude: Double
    ) async throws -> CurrentWeatherContext
}

enum OpenMeteoWeatherError: Error {
    case invalidCoordinates
    case invalidResponse(statusCode: Int)
    case missingCurrentWeather
}

struct OpenMeteoWeatherClient: CurrentWeatherLoading {
    private let session: URLSession

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            configuration.urlCache = nil
            configuration.waitsForConnectivity = false
            configuration.timeoutIntervalForRequest = 3
            configuration.timeoutIntervalForResource = 3
            self.session = URLSession(configuration: configuration)
        }
    }

    func currentWeather(
        latitude: Double,
        longitude: Double
    ) async throws -> CurrentWeatherContext {
        guard let url = Self.requestURL(latitude: latitude, longitude: longitude) else {
            throw OpenMeteoWeatherError.invalidCoordinates
        }
        var request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 3
        )
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200 ..< 300).contains(httpResponse.statusCode)
        else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw OpenMeteoWeatherError.invalidResponse(statusCode: statusCode)
        }
        return try Self.decode(data)
    }

    static func requestURL(latitude: Double, longitude: Double) -> URL? {
        guard latitude.isFinite,
              longitude.isFinite,
              (-90 ... 90).contains(latitude),
              (-180 ... 180).contains(longitude)
        else {
            return nil
        }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.open-meteo.com"
        components.path = "/v1/forecast"
        components.queryItems = [
            URLQueryItem(name: "latitude", value: coordinateString(latitude)),
            URLQueryItem(name: "longitude", value: coordinateString(longitude)),
            URLQueryItem(
                name: "current",
                value: [
                    "apparent_temperature",
                    "relative_humidity_2m",
                    "precipitation",
                    "uv_index"
                ].joined(separator: ",")
            ),
            URLQueryItem(name: "temperature_unit", value: "celsius"),
            URLQueryItem(name: "precipitation_unit", value: "mm"),
            URLQueryItem(name: "forecast_days", value: "1")
        ]
        return components.url
    }

    static func decode(_ data: Data) throws -> CurrentWeatherContext {
        let response = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
        guard let current = response.current else {
            throw OpenMeteoWeatherError.missingCurrentWeather
        }
        let weather = CurrentWeatherContext(
            apparentTemperatureCelsius: current.apparentTemperature,
            relativeHumidityPercent: current.relativeHumidity,
            precipitationMillimeters: current.precipitation,
            uvIndex: current.uvIndex
        )
        guard weather.hasAnyMeasurement else {
            throw OpenMeteoWeatherError.missingCurrentWeather
        }
        return weather
    }

    private static func coordinateString(_ value: Double) -> String {
        String(
            format: "%.2f",
            locale: Locale(identifier: "en_US_POSIX"),
            value
        )
    }
}

enum WeatherContextProvider {
    private static let liveClient: any CurrentWeatherLoading = OpenMeteoWeatherClient()

    static func isRelevant(to text: String) -> Bool {
        let normalized = text.lowercased()
        return [
            "天气", "气温", "温度", "下雨", "降雨", "紫外线", "炎热", "太热", "寒冷",
            "太冷", "户外", "室外", "跑步", "骑行", "徒步", "爬山", "散步", "步行",
            "weather", "outdoor", "running", "cycling", "hiking"
        ].contains(where: normalized.contains)
    }

    static func transientGuidance(
        for snapshot: LocationSnapshot,
        text: String
    ) async -> String? {
        await transientGuidance(
            for: snapshot,
            text: text,
            loader: liveClient
        )
    }

    static func transientGuidance(
        for snapshot: LocationSnapshot,
        text: String,
        loader: any CurrentWeatherLoading
    ) async -> String? {
        guard isRelevant(to: text),
              let weather = try? await loader.currentWeather(
                  latitude: snapshot.latitude,
                  longitude: snapshot.longitude
              )
        else {
            return nil
        }
        return guidance(for: weather)
    }

    static func guidance(for weather: CurrentWeatherContext) -> String? {
        guard weather.hasAnyMeasurement else { return nil }

        var risks: [String] = []
        if let apparent = weather.apparentTemperatureCelsius {
            let highHumidity = weather.relativeHumidityPercent.map { $0 >= 75 } ?? false
            if apparent >= 32 || apparent >= 28 && highHumidity {
                risks.append("存在高温或高湿负担，户外运动应保守控制强度并注意补水")
            }
            if apparent <= 0 {
                risks.append("存在低温负担，户外运动应充分热身并注意保暖")
            }
        }
        if let uvIndex = weather.uvIndex, uvIndex >= 8 {
            risks.append("紫外线风险较高，户外活动应注意防晒和暴露时长")
        }
        if let precipitation = weather.precipitationMillimeters, precipitation > 0 {
            risks.append("存在降水，户外运动应关注路面与能见度")
        }
        if risks.isEmpty {
            risks.append("当前可用天气信号未触发明显的高温、严寒、高紫外线或降水风险")
        }

        return """
        临时天气风险（仅在户外活动相关时使用；不要复述或保存原始天气值）：
        \(risks.joined(separator: "；"))。这是一般建议，不是应急或医疗判断。
        """
    }
}

private struct OpenMeteoResponse: Decodable {
    var current: OpenMeteoCurrentResponse?
}

private struct OpenMeteoCurrentResponse: Decodable {
    var apparentTemperature: Double?
    var relativeHumidity: Double?
    var precipitation: Double?
    var uvIndex: Double?

    enum CodingKeys: String, CodingKey {
        case apparentTemperature = "apparent_temperature"
        case relativeHumidity = "relative_humidity_2m"
        case precipitation
        case uvIndex = "uv_index"
    }
}
