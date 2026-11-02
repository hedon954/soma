import Foundation
import SwiftData
import SwiftOpenAI

enum AgentEnergyContextSchema {
    static var parameters: JSONSchema {
        func text(_ description: String) -> JSONSchema {
            .init(type: .string, description: description)
        }
        func number(_ description: String) -> JSONSchema {
            .init(type: .number, description: description)
        }
        func flag(_ description: String) -> JSONSchema {
            .init(type: .boolean, description: description)
        }
        let fields: [String: JSONSchema] = [
            "work_posture": .init(type: .string, description: "用户明确的主要工作姿势", enum: ["sitting", "standing", "walking"]),
            "work_hours": number("每个工作日工时，0 到 24；未说明不填写"),
            "work_days_per_week": .init(type: .integer, description: "每周工作天数，0 到 7"),
            "commuting_description": text("用户明确提供的通勤方式，不猜测"),
            "commuting_walk_minutes": number("每个工作日通勤步行分钟，0 到 1440，不含跑步训练"),
            "housework_description": text("用户明确提供的家务情况"),
            "housework_minutes": number("平均每天家务分钟，0 到 1440"),
            "food_complete": flag("只有用户明确确认该日全部饮食已记录才为 true，明确有漏记为 false；未知省略"),
            "training_complete": flag("只有用户明确确认全部训练已记录或确无训练才为 true；未知省略"),
            "walking_coverage_complete": flag("用户明确确认全天携带手机或佩戴计步设备才为 true；不能由有样本推断"),
            "fluid_change_concern": flag("用户明确提到近期体液变化疑问、刚开始节食或大改碳水等；不诊断")
        ]
        return .init(type: .object, properties: [
            "date_from": text("明确范围起日 YYYY-MM-DD，含当天；省略用本条用户消息日期"),
            "date_to": text("明确范围止日 YYYY-MM-DD，含当天；最多连续 31 日，不得扩张用户确认范围"),
            "energy_context": .init(type: .object, properties: fields, additionalProperties: false)
        ], required: ["energy_context"], additionalProperties: false)
    }
}

@MainActor
enum AgentEnergyContextTool {
    static func execute(_ arguments: AgentToolArguments, sourceDate: Date, sourceTurnID: UUID?, in context: ModelContext) -> AgentToolResult {
        do {
            guard let input = arguments.energyContext, input.hasLifestyle || input.hasConfirmation else { throw EnergyCalculationError.invalidInput }
            let dates = try EnergyContextStore.dates(from: arguments.dateFrom, to: arguments.dateTo, anchor: sourceDate)
            let count = try EnergyContextStore.save(input, dates: dates, sourceTurnID: sourceTurnID, in: context)
            return .success((count == 0 ? "已有相同的生活与完整性事实。" : "已保存 \(count) 个日期的生活与完整性事实。")
                + "可在能量依据的“生活与记录确认”中查看、修改和删除；未知项保持未知。")
        } catch is EnergyCalculationError {
            return .failure("生活与完整性事实未保存：请提供有效日期、明确事实及合理时长；最多连续 31 日，日期不能晚于本条消息。",
                            code: "invalid_argument", field: "energy_context", expected: "explicit facts with valid dates and durations")
        } catch {
            return .failure("生活与完整性事实暂时无法保存，已有记录保留，请稍后重试。", code: "save_failed")
        }
    }
}
