import Foundation

/// 纪要风格模板：决定 AI 输出的结构。内置三种 + 支持用户自定义。
public struct MinutesTemplate: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var isBuiltin: Bool
    /// 期望输出的小节标题（Markdown 二级标题），如 ["结论", "行动项", "待跟进"]。
    public var sections: [String]
    public var systemPrompt: String
    /// 用户消息模板，必须包含 {transcript} 占位符。
    public var userPromptTemplate: String

    public init(
        id: String,
        name: String,
        isBuiltin: Bool,
        sections: [String],
        systemPrompt: String,
        userPromptTemplate: String
    ) {
        self.id = id
        self.name = name
        self.isBuiltin = isBuiltin
        self.sections = sections
        self.systemPrompt = systemPrompt
        self.userPromptTemplate = userPromptTemplate
    }

    public static let builtins: [MinutesTemplate] = [.work, .meeting, .lecture]

    private static let work = MinutesTemplate(
        id: "builtin.work",
        name: "工作纪要",
        isBuiltin: true,
        sections: ["结论", "行动项", "待跟进"],
        systemPrompt: "你是专业的工作纪要助手。输出简洁的工作纪要，必须使用指定的小节标题。行动项需提炼负责人与截止时间（如原文提及）。全程使用中文。",
        userPromptTemplate: "请根据以下会议转写内容生成「工作纪要」，必须使用指定小节标题。\n\n转写内容：\n{transcript}"
    )

    private static let meeting = MinutesTemplate(
        id: "builtin.meeting",
        name: "会议纪要",
        isBuiltin: true,
        sections: ["议题", "讨论要点", "决议", "待办"],
        systemPrompt: "你是专业的会议纪要助手。输出结构清晰的会议纪要，必须使用指定的小节标题。决议与待办需明确。全程使用中文。",
        userPromptTemplate: "请根据以下会议转写内容生成「会议纪要」，必须使用指定小节标题。\n\n转写内容：\n{transcript}"
    )

    private static let lecture = MinutesTemplate(
        id: "builtin.lecture",
        name: "课程纪要",
        isBuiltin: true,
        sections: ["知识点", "重点难点", "疑问", "复习建议"],
        systemPrompt: "你是专业的课程笔记助手。输出适合复习的课程纪要，必须使用指定的小节标题。重点难点需突出。全程使用中文。",
        userPromptTemplate: "请根据以下课堂转写内容生成「课程纪要」，必须使用指定小节标题。\n\n转写内容：\n{transcript}"
    )
}
