import Foundation
import Testing
@testable import FlashNoteCore

/// 测试替身：按预设响应回复 complete；记录调用。
final class MockLLMClient: LLMClient {
    let modelName = "mock-model"
    var onComplete: (([ChatMessage]) -> String)?
    private(set) var calls: [[ChatMessage]] = []

    func complete(messages: [ChatMessage]) async throws -> String {
        calls.append(messages)
        return onComplete?(messages) ?? ""
    }

    func stream(messages: [ChatMessage]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(onComplete?(messages) ?? "")
            continuation.finish()
        }
    }
}

struct MinutesGeneratorTests {
    private let recordingID = UUID()

    @Test func shortTranscriptSingleCallAndSections() async throws {
        let client = MockLLMClient()
        client.onComplete = { messages in
            #expect(messages.count == 2) // system + user
            #expect(messages[0].role == .system)
            #expect(messages[1].content.contains("转写内容"))
            #expect(messages[1].content.contains("不要新增其他小节"))
            return """
            ## 结论
            通过可插拔转写架构。

            ## 行动项
            - 张伟：完成接口定义

            ## 待跟进
            下周评审。
            """
        }
        let generator = MinutesGenerator(client: client)
        let minutes = try await generator.generate(
            transcript: "这是一段很短的转写。",
            template: .builtins[0],
            recordingID: recordingID
        )
        #expect(client.calls.count == 1)
        #expect(minutes.recordingID == recordingID)
        #expect(minutes.templateID == "builtin.work")
        #expect(minutes.styleName == "工作纪要")
        #expect(minutes.model == "mock-model")
        #expect(minutes.sections.count == 3)
        #expect(minutes.sections[0].title == "结论")
        #expect(minutes.sections[0].body.contains("可插拔"))
        #expect(minutes.sections[1].title == "行动项")
    }

    @Test func customTemplateWithoutPlaceholderStillGetsTranscript() async throws {
        let client = MockLLMClient()
        client.onComplete = { messages in
            #expect(messages[1].content.contains("转写内容"))
            #expect(messages[1].content.contains("这是一段待纪要的转写"))
            #expect(messages[1].content.contains("不要新增其他小节"))
            return "## 结论\nOK。\n## 行动项\n\n## 待跟进\n"
        }
        let template = MinutesTemplate(
            id: "custom-no-placeholder",
            name: "自定义",
            isBuiltin: false,
            sections: ["结论", "行动项", "待跟进"],
            systemPrompt: "你是助手。",
            userPromptTemplate: "请生成纪要。"
        )
        let minutes = try await MinutesGenerator(client: client).generate(
            transcript: "这是一段待纪要的转写",
            template: template,
            recordingID: recordingID
        )
        #expect(minutes.sections[0].body == "OK。")
    }

    @Test func longTranscriptChunkedBeforeFinalCall() async throws {
        let client = MockLLMClient()
        client.onComplete = { messages in
            // 第一轮：片段摘要调用，system 为摘要指令
            if messages[0].content.contains("摘要") {
                return "片段要点。"
            }
            return """
            ## 结论
            结论内容。

            ## 行动项
            行动项内容。

            ## 待跟进
            待跟进内容。
            """
        }
        let longText = String(repeating: "这是很长的一段会议内容。", count: 200)
        let generator = MinutesGenerator(
            client: client,
            chunker: TranscriptChunker(maxChars: 100)
        )
        let minutes = try await generator.generate(
            transcript: longText,
            template: .builtins[0],
            recordingID: recordingID
        )
        // 分段调用 + 最终生成调用
        #expect(client.calls.count > 1)
        #expect(minutes.sections.count == 3)
    }

    @Test func missingSectionFilledEmpty() async throws {
        let client = MockLLMClient()
        client.onComplete = { _ in "## 结论\n只有结论。" }
        let generator = MinutesGenerator(client: client)
        let minutes = try await generator.generate(
            transcript: "短文本。",
            template: .builtins[0],
            recordingID: recordingID
        )
        #expect(minutes.sections.count == 3)
        #expect(minutes.sections[0].title == "结论")
        #expect(!minutes.sections[0].body.isEmpty)
        #expect(minutes.sections[1].body == "")
        #expect(minutes.sections[2].body == "")
    }

    @Test func minutesCodable() throws {
        let minutes = Minutes(
            id: UUID(),
            recordingID: recordingID,
            templateID: "builtin.work",
            styleName: "工作纪要",
            sections: [MinutesSection(title: "结论", body: "x")],
            model: "mock",
            promptVersion: "1",
            generatedAt: Date(timeIntervalSince1970: 100)
        )
        let data = try JSONEncoder().encode(minutes)
        let decoded = try JSONDecoder().decode(Minutes.self, from: data)
        #expect(decoded == minutes)
    }

    @Test func parseSectionsToleratesHeaderVariants() {
        let output = """
        开头前言（应被丢弃）。

        ##结论
        结论正文。

        ### 行动项
        行动项正文。

        ## 待跟进：
        待跟进正文。
        """
        let sections = MinutesGenerator.parseSections(output, expected: ["结论", "行动项", "待跟进"])
        #expect(sections.count == 3)
        #expect(sections[0].body.contains("结论正文"))
        #expect(sections[1].body.contains("行动项正文"))
        #expect(sections[2].body.contains("待跟进正文"))
    }
}
