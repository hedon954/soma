import Foundation

/// 每条消息固定显示日期和时间；跨年时补年份。位置缺失时不留占位符。
enum ChatMessageMetaLine {
    enum HorizontalAlignment: Equatable, Sendable {
        case leading
        case trailing
    }

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

    /// 消息元信息的位置只由发送方决定，不能随流式生命周期改变。
    /// AI 回复固定在左下角，用户消息固定在右下角。
    static func horizontalAlignment(isFromCoach: Bool) -> HorizontalAlignment {
        isFromCoach ? .leading : .trailing
    }

    static func timeText(
        for date: Date,
        now: Date,
        calendar: Calendar
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        let includesYear = calendar.component(.year, from: date)
            != calendar.component(.year, from: now)
        formatter.dateFormat = includesYear ? "yyyy年M月d日 HH:mm" : "M月d日 HH:mm"
        return formatter.string(from: date)
    }
}
