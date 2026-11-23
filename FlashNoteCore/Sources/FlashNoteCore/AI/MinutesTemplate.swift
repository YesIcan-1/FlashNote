import Foundation

/// 纪要风格模板：决定 AI 输出的结构。
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

    public static let builtins: [MinutesTemplate] = [.meeting, .work, .project, .interview, .brainstorm, .lecture]
    public static let defaultTemplate = meeting

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
        sections: ["会议主题", "内容总结", "会议信息", "会议议题", "会议结论", "待办"],
        systemPrompt: "你是严谨的中文会议记录员。只根据真实转写整理事实、观点和决定，不编造姓名、时间、地点、数字、政策、决议或责任人。保留关键数据和有分歧的意见，并明确区分已决定、建议与待确认。会议主题用简短标题，若转写明确给出会议日期，可在标题前加月日；否则不要推测日期。内容总结写一段连贯的概览。会议议题按主题、子议题、具体事实三级组织，避免把整场讨论压成几条笼统要点。会议结论只写有依据的结论，未形成结论时明确说明。待办只列真实提出的动作；负责人、期限仅在原文明确时写出。全程使用中文。",
        userPromptTemplate: "请按以下版式整理真实转写：\n1. 会议主题：一行简短标题，不要 Markdown 标题。\n2. 内容总结：一段完整概览，概括讨论范围和主要结果，不重复下方细节。\n3. 会议信息：使用 Markdown 两列表格，表头为「项目 | 描述」，行依次为会议时间、会议地点、参会成员；原文未提及的值写「未提及」，不能用录音时间冒充会议时间。\n4. 会议议题：用 Markdown 缩进列表分层组织，一级为主题、二级为子议题、三级为有依据的具体观点、数据或分歧；分别以「- 」「  - 」「    - 」开头。按真实内容决定条目数，不为凑数量编写。\n5. 会议结论：用条目概括已形成的结论；建议或风险必须标明性质。未形成结论时写「未明确」。\n6. 待办：一项一行，以「- 」开头；没有明确待办时写「未明确」。\n保留重要数字和专有名词，无法辨认的内容标注待核实。不要输出没有依据的推断。\n\n转写内容：\n{transcript}"
    )

    private static let project = MinutesTemplate(
        id: "builtin.project", name: "项目复盘", isBuiltin: true,
        sections: ["项目目标", "进展与成果", "问题与原因", "改进动作"],
        systemPrompt: "你是项目复盘记录员。只根据真实转写概括目标、进展、问题和具体改进动作，不补写不存在的结果或责任人。使用中文。",
        userPromptTemplate: "请把以下转写整理成项目复盘，明确事实与推测。\n\n转写内容：\n{transcript}"
    )

    private static let interview = MinutesTemplate(
        id: "builtin.interview", name: "访谈记录", isBuiltin: true,
        sections: ["访谈主题", "核心观点", "关键引述", "待核实问题"],
        systemPrompt: "你是访谈整理员。保留受访者观点和上下文，只能使用转写中确有的引述，不编造身份、观点或话语。使用中文。",
        userPromptTemplate: "请把以下转写整理成访谈记录，区分受访者原话与整理者概括。\n\n转写内容：\n{transcript}"
    )

    private static let brainstorm = MinutesTemplate(
        id: "builtin.brainstorm", name: "头脑风暴", isBuiltin: true,
        sections: ["讨论目标", "创意方向", "筛选依据", "下一步实验"],
        systemPrompt: "你是创意讨论记录员。按方向归纳真实提出的想法，保留有分歧的意见；不得把未决定的想法写成决议。使用中文。",
        userPromptTemplate: "请把以下转写整理成头脑风暴记录。\n\n转写内容：\n{transcript}"
    )

    private static let lecture = MinutesTemplate(
        id: "builtin.lecture",
        name: "课程纪要",
        isBuiltin: true,
        sections: ["知识点", "重点难点", "疑问", "复习建议"],
        systemPrompt: "你是专业的课程笔记助手。输出适合复习的课程纪要，必须使用指定的小节标题。重点难点需突出。全程使用中文。",
        userPromptTemplate: "请根据以下课堂转写内容生成「课程纪要」，必须使用指定小节标题。\n\n转写内容：\n{transcript}"
    )

    public static let mindMap = MinutesTemplate(
        id: "builtin.mindmap", name: "思维导图", isBuiltin: true,
        sections: ["核心主题", "主题结构"],
        systemPrompt: "你是严谨的信息架构师。只根据真实转写建立详细的思维导图，不编造事实。围绕核心主题提炼4至8个一级分支；每个一级分支尽可能含2至5个二级节点，必要时增加第三级节点。保留关键事实、数字、观点之间的关系以及待办。每个节点用短语，避免整段文字。使用中文。",
        userPromptTemplate: "请根据以下转写生成可交互思维导图的数据。严格使用两个小节标题：核心主题用一行短语；主题结构用 Markdown 缩进列表，一级分支以“- ”开头，二级缩进两个空格，第三级缩进四个空格。尽可能覆盖背景、核心观点、证据、结论和待办，但只列转写中真实存在的内容。\n\n转写内容：\n{transcript}"
    )

    public static let insight = MinutesTemplate(
        id: "builtin.insight", name: "洞察", isBuiltin: true,
        sections: ["洞察提炼", "启发思考"],
        systemPrompt: "你是严谨的中文分析助手。仅从提供的转写中提炼观点，不编造姓名、事实、数字或引语。区分说话人的观点和你的分析；不确定时明确说明。",
        userPromptTemplate: "根据以下真实转写，提炼最有价值的观点和后续启发。必须用中文，简洁、有依据，不重复原文的冗长表述。\n\n转写内容：\n{transcript}"
    )
}
