import Foundation

enum BusinessDateResolver {
    static func startOfDay(_ date: Date, in timeZone: TimeZone) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.startOfDay(for: date)
    }

    /// 将原始 Turn 的本地时分秒稳定映射到业务日。夏令时缺口由 Calendar 选择下一有效时刻。
    static func defaultOccurredAt(
        turnSentAt: Date,
        businessDate: Date,
        timeZone: TimeZone
    ) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let day = calendar.dateComponents([.year, .month, .day], from: businessDate)
        let time = calendar.dateComponents(
            [.hour, .minute, .second, .nanosecond],
            from: turnSentAt
        )
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = timeZone
        components.year = day.year
        components.month = day.month
        components.day = day.day
        components.hour = time.hour
        components.minute = time.minute
        components.second = time.second
        components.nanosecond = time.nanosecond
        return calendar.date(from: components)
            ?? calendar.nextDate(
                after: startOfDay(businessDate, in: timeZone),
                matching: time,
                matchingPolicy: .nextTime
            )
            ?? startOfDay(businessDate, in: timeZone)
    }

    /// 明确日期只影响当前 Turn，不修改 Session。具体日期优先于相对日期。
    static func turnBusinessDate(
        in text: String,
        sessionBusinessDate: Date,
        turnSentAt: Date,
        timeZone: TimeZone
    ) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        if let explicit = explicitDate(in: text, turnSentAt: turnSentAt, calendar: calendar) {
            return calendar.startOfDay(for: explicit)
        }
        if text.contains("昨天") || text.contains("昨日") {
            return calendar.date(
                byAdding: .day,
                value: -1,
                to: calendar.startOfDay(for: turnSentAt)
            ) ?? calendar.startOfDay(for: turnSentAt)
        }
        if text.contains("今天") || text.contains("今日") {
            return calendar.startOfDay(for: turnSentAt)
        }
        return calendar.startOfDay(for: sessionBusinessDate)
    }

    private static func explicitDate(
        in text: String,
        turnSentAt: Date,
        calendar: Calendar
    ) -> Date? {
        let patterns = [
            (#"(?<!\d)(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})(?!\d)"#, true),
            (#"(?<!\d)(\d{4})年(\d{1,2})月(\d{1,2})日?"#, true),
            (#"(?<!\d)(\d{1,2})月(\d{1,2})日?"#, false)
        ]
        for (pattern, includesYear) in patterns {
            guard let components = dateComponents(
                      matching: pattern,
                      in: text,
                      includesYear: includesYear,
                      turnSentAt: turnSentAt,
                      calendar: calendar
                  ),
                  let date = calendar.date(from: components),
                  calendar.component(.year, from: date) == components.year,
                  calendar.component(.month, from: date) == components.month,
                  calendar.component(.day, from: date) == components.day
            else { continue }
            return date
        }
        return nil
    }

    private static func dateComponents(
        matching pattern: String,
        in text: String,
        includesYear: Bool,
        turnSentAt: Date,
        calendar: Calendar
    ) -> DateComponents? {
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(
                  in: text,
                  range: NSRange(text.startIndex..., in: text)
              )
        else { return nil }
        let values = (1 ..< match.numberOfRanges).compactMap { index -> Int? in
            guard let range = Range(match.range(at: index), in: text) else { return nil }
            return Int(text[range])
        }
        let year = includesYear ? values.first : calendar.component(.year, from: turnSentAt)
        let offset = includesYear ? 1 : 0
        guard let year, values.count >= offset + 2 else { return nil }
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = year
        components.month = values[offset]
        components.day = values[offset + 1]
        return components
    }
}
