import Foundation

enum ReActAgentPrompt {
    static let system = SomaPrompt.text("coach_system_prompt")

    static func user(
        text: String,
        context: String,
        imageCount: Int,
        hasVideo: Bool,
        directVideoCount: Int = 0,
        imageAttachmentCount: Int? = nil,
        videoAttachmentCount: Int? = nil,
        configuration: AgentPromptConfiguration
    ) -> String {
        if configuration.scene == .performanceReview {
            return text
        }

        let skills: String
        if let selected = configuration.skills.first(where: { $0.id == configuration.selectedSkillID }) {
            skills = "选中 Skill：\(selected.name ?? selected.id)\n\n\(selected.content)"
        } else {
            let catalog = configuration.skills.map {
                "- name: \($0.id)\n  description: \($0.description ?? "")\n  when_to_use: \($0.whenToUse ?? "")"
            }.joined(separator: "\n")
            skills = catalog.isEmpty ? "无可用 Skill。" : catalog
        }

        let media: String
        if (imageAttachmentCount ?? imageCount) == 0, (videoAttachmentCount ?? 0) == 0, !hasVideo {
            media = "无媒体。"
        } else {
            let originalImages = imageAttachmentCount ?? imageCount
            let originalVideos = videoAttachmentCount ?? (hasVideo ? 1 : 0)
            media = """
            原始附件：\(originalImages) 张图片、\(originalVideos) 个视频。
            当前请求实际提供：\(imageCount) 张图片、\(directVideoCount) 个完整视频。
            """
        }
        let normalizedContext = context.trimmingCharacters(in: .whitespacesAndNewlines)
        return SomaPrompt.text("coach_user_prompt", [
            "persona": configuration.coachPersona ?? "沿用本次任务已冻结的偏好。",
            "context": normalizedContext.isEmpty ? "无本机上下文。" : normalizedContext,
            "skills": skills,
            "text": text.isEmpty ? "无文字。" : text,
            "media": media
        ])
    }

    static func historicalUser(
        text: String,
        imageCount: Int,
        imageAttachmentCount: Int,
        videoAttachmentCount: Int,
        canReferenceImagesAsRecentGymTurn: Bool = false
    ) -> String {
        let mediaReference = if canReferenceImagesAsRecentGymTurn {
            """

            这条是当前输入紧邻的上一轮，原始图片可供本轮健身房写入引用。
            """
        } else {
            ""
        }
        return """
        历史用户输入：
        \(text.isEmpty ? "无文字。" : text)

        该轮原始附件：\(imageAttachmentCount) 张图片、\(videoAttachmentCount) 个视频；
        本次随 Session 上下文重新提供图片 \(imageCount) 张；视频以完整文件附件为准。
        没有重新提供的历史画面不可凭文字提示臆测。
        \(mediaReference)
        """
    }
}
