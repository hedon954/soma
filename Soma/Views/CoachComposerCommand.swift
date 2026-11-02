import Foundation

@MainActor
enum CoachComposerCommand {
    static var pendingSend: String?
    static let energyContextOpening = "帮我完善消耗估算用的生活信息。先看我已经提供的事实，只补工作主要坐着、站着还是走动，以及通勤和家务大概怎样，不让我选择活动系数。"
}
