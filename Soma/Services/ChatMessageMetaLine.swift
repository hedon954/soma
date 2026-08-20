import Foundation

/// PRD 033：每条消息底部一行说明"什么时候发的、在哪发的"。同一天只显示时刻，跨天补日期；
/// 位置缺失时整行只剩时间，不留占位符。
enum ChatMessageMetaLine {
    struct Content: Equatable, Sendable {
        var text: String
        var accessibilityLabel: String
    }

    static func make(
        date: Date,
        locationName: String?,
        isFromCoach: Bool,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Content {
        let time = timeText(for: date, now: now, calendar: calendar)
        let trimmedPlace = locationName?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmedPlace.isEmpty, !isFromCoach else {
            return Content(
                text: time,
                accessibilityLabel: "\(isFromCoach ? "回复" : "发送")于 \(time)"
            )
        }
        return Content(
            text: "\(time) · \(trimmedPlace)",
            accessibilityLabel: "发送于 \(time)，位置 \(trimmedPlace)"
        )
    }

    static func timeText(
        for date: Date,
        now: Date,
        calendar: Calendar
    ) -> String {
        if calendar.isDate(date, inSameDayAs: now) {
            return timeFormatter.string(from: date)
        }
        if let year = calendar.dateComponents([.year], from: date).year,
           let currentYear = calendar.dateComponents([.year], from: now).year,
           year != currentYear
        {
            return yearDayTimeFormatter.string(from: date)
        }
        return dayTimeFormatter.string(from: date)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static let dayTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter
    }()

    private static let yearDayTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月d日 HH:mm"
        return formatter
    }()
}
