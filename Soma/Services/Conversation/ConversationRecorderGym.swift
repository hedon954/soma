import Foundation
import SwiftData

@MainActor
extension ConversationRecorder {
    static func updateGym(
        _ arguments: AgentToolArguments,
        mediaKind: MediaKind,
        mediaPath: String?,
        mediaAttachments: [MediaAttachmentReference],
        in context: ModelContext
    ) -> AgentToolResult {
        let imageAttachments = resolvedMediaAttachments(
            mediaAttachments,
            legacyKind: mediaKind,
            legacyPath: mediaPath
        ).filter { $0.kind == .image }
        if arguments.mediaSource == AgentToolMediaAttribution.recentGymTurn,
           imageAttachments.isEmpty
        {
            return .failure("没有找到紧邻上一轮的健身房照片，请重新附加照片后再试。")
        }

        let gyms = fetchGymsForMutation(in: context)
        let requestedName = arguments.gymName?.trimmed.nilIfEmpty
        let target: GymProfile
        if let requestedName,
           let existing = gyms.first(where: {
               $0.name.localizedCaseInsensitiveContains(requestedName)
                   || requestedName.localizedCaseInsensitiveContains($0.name)
           })
        {
            target = existing
        } else if requestedName == nil, let current = GymSelection.current(in: gyms) {
            target = current
        } else {
            target = GymProfile(
                name: requestedName ?? "新健身房",
                notes: "通过 Agent 对话创建",
                isCurrent: true
            )
            GymSelection.activate(target, among: gyms)
            context.insert(target)
        }

        if let summary = arguments.summary?.trimmed.nilIfEmpty {
            target.notes = summary
        }
        if let coverPath = imageAttachments.first?.path {
            target.coverImagePath = coverPath
            let targetID = target.id
            let existingMedia = (
                try? context.fetch(FetchDescriptor<GymMedia>(
                    predicate: #Predicate { $0.gymID == targetID }
                ))
            ) ?? []
            for attachment in imageAttachments where
                !existingMedia.contains(where: {
                    $0.gymID == target.id && $0.path == attachment.path
                })
            {
                context.insert(GymMedia(gymID: target.id, path: attachment.path))
            }
        }

        let existingEquipment = fetchEquipment(gymID: target.id, in: context)
        for input in arguments.equipment ?? [] {
            let name = input.name.trimmed
            guard !name.isEmpty else { continue }
            if let existing = existingEquipment.first(where: {
                $0.gymID == target.id
                    && $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
            }) {
                existing.category = input.category.trimmed
                existing.capabilities = input.capabilities.trimmed
                existing.confidence = min(max(input.confidence ?? existing.confidence, 0), 1)
                if let imagePath = imageAttachments.first?.path {
                    existing.imagePath = imagePath
                }
            } else {
                context.insert(GymEquipment(
                    gymID: target.id,
                    name: name,
                    category: input.category.trimmed,
                    capabilities: input.capabilities.trimmed,
                    confidence: min(max(input.confidence ?? 0.9, 0), 1),
                    imagePath: imageAttachments.first?.path
                ))
            }
        }
        try? context.save()
        let names = (arguments.equipment ?? []).map(\.name).filter { !$0.isEmpty }
        let detail = names.isEmpty ? "环境信息" : names.joined(separator: "、")
        let photoDetail = imageAttachments.isEmpty
            ? ""
            : "，并保存 \(imageAttachments.count) 张照片"
        return .success(
            "已更新健身房「\(target.name)」：\(detail)\(photoDetail)。",
            recordRefs: [gymReference(target)],
            recordType: .gym
        )
    }

    static func switchGym(
        _ arguments: AgentToolArguments,
        in context: ModelContext
    ) -> AgentToolResult {
        guard let name = arguments.gymName?.trimmed.nilIfEmpty else {
            return .failure("switch_gym 缺少 gym_name。")
        }
        let gyms = fetchGymsForMutation(in: context)
        guard let target = gyms.first(where: {
            $0.name.localizedCaseInsensitiveContains(name)
                || name.localizedCaseInsensitiveContains($0.name)
        }) else {
            let available = gyms.map(\.name).joined(separator: "、")
            return .failure("没有找到「\(name)」。现有健身房：\(available.nilIfEmpty ?? "无")。")
        }
        GymSelection.activate(target, among: gyms)
        try? context.save()
        return .success("当前健身房已切换为「\(target.name)」。", recordType: .switchGym)
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
