import Foundation

/// 纪要的一个分节。
public struct MinutesSection: Codable, Equatable, Sendable {
    public var title: String
    public var body: String

    public init(title: String, body: String) {
        self.title = title
        self.body = body
    }
}

/// AI 生成的纪要。
public struct Minutes: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var recordingID: UUID
    public var templateID: String
    public var styleName: String
    public var sections: [MinutesSection]
    public var model: String
    public var promptVersion: String
    public var generatedAt: Date

    public init(
        id: UUID = UUID(),
        recordingID: UUID,
        templateID: String,
        styleName: String,
        sections: [MinutesSection],
        model: String,
        promptVersion: String = "1",
        generatedAt: Date = Date()
    ) {
        self.id = id
        self.recordingID = recordingID
        self.templateID = templateID
        self.styleName = styleName
        self.sections = sections
        self.model = model
        self.promptVersion = promptVersion
        self.generatedAt = generatedAt
    }
}

/// 基于模板 + LLM 生成纪要。长转写先分块摘要再最终生成，控制 token。
public struct MinutesGenerator {
    private let client: LLMClient
    private let chunker: TranscriptChunker

    public init(client: LLMClient, chunker: TranscriptChunker = TranscriptChunker()) {
        self.client = client
        self.chunker = chunker
    }

    public func generate(
        transcript: String,
        template: MinutesTemplate,
        recordingID: UUID
    ) async throws -> Minutes {
        let prepared: String
        if transcript.count > chunker.maxChars {
            prepared = try await summarizeChunks(transcript)
        } else {
            prepared = transcript
        }

        let messages = [
            ChatMessage(role: .system, content: template.systemPrompt),
            ChatMessage(role: .user, content: makeUserPrompt(template: template, transcript: prepared))
        ]
        let output = try await client.complete(messages: messages)
        let sections = Self.parseSections(output, expected: template.sections)
        return Minutes(
            recordingID: recordingID,
            templateID: template.id,
            styleName: template.name,
            sections: sections,
            model: client.modelName
        )
    }

    private func summarizeChunks(_ transcript: String) async throws -> String {
        let chunks = chunker.chunk(transcript)
        var summaries: [String] = []
        for chunk in chunks {
            let messages = [
                ChatMessage(role: .system, content: "你是会议摘要助手。用简洁的中文要点概括以下转写片段，保留人名、数字与结论。"),
                ChatMessage(role: .user, content: chunk)
            ]
            let summary = try await client.complete(messages: messages)
            summaries.append(summary)
        }
        return summaries.joined(separator: "\n")
    }

    private func makeUserPrompt(template: MinutesTemplate, transcript: String) -> String {
        var prompt = template.userPromptTemplate
        if prompt.contains("{transcript}") {
            prompt = prompt.replacingOccurrences(of: "{transcript}", with: transcript)
        } else {
            // 自定义模板缺少占位符时，直接追加转写内容，避免静默丢失输入
            prompt += "\n\n转写内容：\n\(transcript)"
        }
        let headers = template.sections.map { "## \($0)" }.joined(separator: "\n")
        // 钉死小节格式：防止模型输出 "## 结论：" / "### 结论" 变体导致分节解析静默丢失
        prompt += "\n\n必须严格使用以下小节标题（Markdown 二级标题，标题后不加冒号或编号，不要新增其他小节）：\n\(headers)"
        return prompt
    }

    /// 解析 LLM 输出的 Markdown，按 "## 标题"（容忍 "##标题"/"### 标题"/"## 标题：" 变体）提取各节；缺失的节补空。
    static func parseSections(_ output: String, expected: [String]) -> [MinutesSection] {
        var found: [MinutesSection] = []
        var currentTitle: String?
        var currentBody: [String] = []

        func flush() {
            if let title = currentTitle {
                let body = currentBody.joined(separator: "\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                found.append(MinutesSection(title: title, body: body))
            }
            currentTitle = nil
            currentBody = []
        }

        for line in output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let title = Self.headerTitle(from: trimmed) {
                flush()
                currentTitle = title
            } else if currentTitle != nil {
                currentBody.append(line)
            }
        }
        flush()

        var byTitle: [String: String] = [:]
        for section in found {
            byTitle[section.title] = section.body
        }
        let sections = expected.map { MinutesSection(title: $0, body: byTitle[$0] ?? "") }
        // 兼容常见兼容模型未遵守 Markdown 标题格式的情况：保留完整内容，不能只留下空模板。
        if sections.allSatisfy({ $0.body.isEmpty }) {
            return [MinutesSection(title: "AI 生成结果", body: output.trimmingCharacters(in: .whitespacesAndNewlines))]
        }
        return sections
    }

    /// 把 Markdown 标题行规范化为小节标题：容忍 "##标题"、"### 标题"、尾部冒号（：/:）；非标题行返回 nil。
    static func headerTitle(from line: String) -> String? {
        let unbolded = line.trimmingCharacters(in: CharacterSet(charactersIn: "*"))
        guard unbolded.hasPrefix("#") else { return nil }
        var rest = unbolded
        while rest.hasPrefix("#") { rest.removeFirst() }
        let title = rest.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return nil }
        let normalized = title.trimmingCharacters(in: CharacterSet(charactersIn: "：:"))
        guard !normalized.isEmpty else { return nil }
        return normalized
    }
}
