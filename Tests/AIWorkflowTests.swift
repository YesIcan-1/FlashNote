import Foundation
import Testing
import FlashNoteCore
#if os(macOS)
@testable import FlashNoteMac
#else
@testable import FlashNote
#endif

struct AIWorkflowTests {
    private struct StubLLM: LLMClient {
        let modelName = "test-model"
        func complete(messages: [ChatMessage]) async throws -> String {
            let prompt = messages.last?.content ?? ""
            if prompt.contains("## 核心主题") {
                return "## 核心主题\n项目推进\n## 主题结构\n- 进度\n  - 完成设计\n- 风险\n  - 人手不足"
            }
            if prompt.contains("## 洞察提炼") {
                return "## 洞察提炼\n资源约束影响排期\n## 启发思考\n先确认资源"
            }
            return "## 会议主题\n**项目排期讨论**\n## 讨论要点\n讨论资源\n## 决议\n确认排期\n## 待办\n核实人手"
        }
        func stream(messages: [ChatMessage]) -> AsyncThrowingStream<String, Error> {
            AsyncThrowingStream { $0.finish() }
        }
    }

    private struct DelayedMeetingLLM: LLMClient {
        let modelName = "delayed-test"
        func complete(messages: [ChatMessage]) async throws -> String {
            try await Task.sleep(nanoseconds: 80_000_000)
            return "## 会议主题\n后台生成测试\n## 内容总结\n会议讨论排期。\n## 会议信息\n| 项目 | 描述 |\n| --- | --- |\n| 会议时间 | 未提及 |\n## 会议议题\n- 排期\n## 会议结论\n- 已确认排期\n## 待办\n未明确"
        }
        func stream(messages: [ChatMessage]) -> AsyncThrowingStream<String, Error> {
            AsyncThrowingStream { $0.finish() }
        }
    }

    @Test func meetingMinutesAreTheDefault() {
        #expect(MinutesTemplate.defaultTemplate.id == "builtin.meeting")
        #expect(MinutesTemplate.builtins.first?.id == "builtin.meeting")
    }

    @Test func titleComesFromExplicitMeetingTopicOnly() {
        let recordingID = UUID()
        let minutes = Minutes(recordingID: recordingID, templateID: "builtin.meeting", styleName: "会议纪要",
            sections: [MinutesSection(title: "会议主题", body: "**下季度产品发布计划**\n其它内容"),
                       MinutesSection(title: "待办", body: "- 完成评审")], model: "test")
        #expect(RecordingTitle.shortTitle(from: minutes) == "下季度产品发布计划")
        let noTopic = Minutes(recordingID: recordingID, templateID: "builtin.meeting", styleName: "会议纪要",
            sections: [MinutesSection(title: "会议主题", body: "未明确")], model: "test")
        #expect(RecordingTitle.shortTitle(from: noTopic) == nil)
    }

    @Test func existingDeviceTitleIsBackfilledWithoutChangingCustomName() throws {
        let store = InMemoryStore()
        let device = Recording(title: "note20261029-010203", status: .transcribed)
        let custom = Recording(title: "我的采访", status: .transcribed)
        try store.upsertRecording(device)
        try store.upsertRecording(custom)
        for recording in [device, custom] {
            try store.upsertMinutes(Minutes(recordingID: recording.id, templateID: "builtin.meeting",
                styleName: "会议纪要", sections: [MinutesSection(title: "议题", body: "项目版本发布，讨论上线计划")], model: "test"))
        }
        #expect(try RecordingTitle.backfillHardwareTitles(in: store) == 1)
        #expect(try store.fetchRecording(id: device.id)?.title == "项目版本发布")
        #expect(try store.fetchRecording(id: custom.id)?.title == "我的采访")
    }

    @Test func longMeetingTopicUsesFirstCompletePhrase() throws {
        let store = InMemoryStore()
        let device = Recording(title: "note20261029-010203", status: .transcribed)
        let oldGenerated = Recording(title: "本次会议围绕项目投资与产品调整、现场及人", status: .summarized)
        let oldShortTitle = Recording(title: "围绕发言人九年记者职业经历", status: .summarized)
        try store.upsertRecording(device)
        try store.upsertRecording(oldGenerated)
        try store.upsertRecording(oldShortTitle)
        for recording in [device, oldGenerated] {
            try store.upsertMinutes(Minutes(recordingID: recording.id, templateID: "builtin.meeting",
                styleName: "会议纪要", sections: [MinutesSection(title: "会议主题", body: "本次会议围绕项目投资与产品调整、现场及人员安排进行讨论")], model: "test"))
        }
        try store.upsertMinutes(Minutes(recordingID: oldShortTitle.id, templateID: "builtin.meeting",
            styleName: "会议纪要", sections: [MinutesSection(title: "议题", body: "围绕发言人九年记者职业经历，讨论成长路径")], model: "test"))
        #expect(try RecordingTitle.backfillHardwareTitles(in: store) == 3)
        #expect(try store.fetchRecording(id: device.id)?.title == "项目投资与产品调整")
        #expect(try store.fetchRecording(id: oldGenerated.id)?.title == "项目投资与产品调整")
        #expect(try store.fetchRecording(id: oldShortTitle.id)?.title == "发言人九年记者职业经历")
    }

    @Test func mindMapKeepsThreeLevels() {
        let minutes = Minutes(recordingID: UUID(), templateID: "builtin.mindmap", styleName: "思维导图",
            sections: [MinutesSection(title: "核心主题", body: "项目推进"),
                       MinutesSection(title: "主题结构", body: "- 进度\n  - 设计\n    - 完成原型\n  - 开发\n- 风险\n  - 人力")], model: "test")
        let outline = MindMapOutline(minutes: minutes, fallbackTitle: "录音")
        #expect(outline.title == "项目推进")
        #expect(outline.branches.count == 2)
        #expect(outline.branches[0].children[0].children[0].title == "完成原型")
        #expect(outline.branches[1].children[0].title == "人力")
    }

    @Test func newRecordingTitleMatchesHardwarePattern() {
        let title = RecorderViewModel.hardwareStyleTitle(at: Date(timeIntervalSince1970: 0))
        #expect(title.range(of: #"^note\d{8}-\d{6}$"#, options: .regularExpression) != nil)
    }

    @Test func successfulTranscriptGeneratesMinutesAndInsightWithoutMindMap() async throws {
        let store = InMemoryStore()
        let id = UUID()
        try store.upsertRecording(Recording(id: id, title: "note20261029-010203", status: .transcribed))
        try store.upsertTranscript(Transcript(recordingID: id,
            segments: [TranscriptSegment(startTime: 0, text: "讨论项目排期和资源")]))
        let settings = AppSettings(storeDirectory: URL(fileURLWithPath: "/tmp"), keychain: MockKeychain(),
                                   defaults: UserDefaults(suiteName: "workflow-\(UUID().uuidString)")!)
        settings.llmAPIKey = "test-key"
        let processing = RecordingProcessingCoordinator(store: store, settingsFactory: { settings },
                                                         clientFactory: { _, _, _ in StubLLM() })
        processing.beginTranscription(id)
        await processing.generateAll(recordingID: id)
        #expect(processing.progress[id]?.stage == .completed)
        #expect(processing.progress[id]?.finishedSteps == 3)
        #expect(try store.fetchRecording(id: id)?.title == "项目排期讨论")
        #expect(try store.fetchRecording(id: id)?.status == .summarized)
        #expect(try store.fetchMinutes(recordingID: id).map(\.templateID) ==
                ["builtin.meeting", "builtin.insight"])
    }

    @Test func manualMinutesGenerationIsOwnedByCoordinator() async throws {
        let store = InMemoryStore()
        let id = UUID()
        try store.upsertRecording(Recording(id: id, title: "note20261030-120000", status: .transcribed))
        try store.upsertTranscript(Transcript(recordingID: id,
            segments: [TranscriptSegment(startTime: 0, text: "会议讨论排期并确认计划")]))
        let settings = AppSettings(storeDirectory: URL(fileURLWithPath: "/tmp"), keychain: MockKeychain(),
                                   defaults: UserDefaults(suiteName: "background-minutes-\(UUID().uuidString)")!)
        settings.llmAPIKey = "test-key"
        var notices: [WorkflowNoticeKind] = []
        let processing = RecordingProcessingCoordinator(store: store, settingsFactory: { settings },
            clientFactory: { _, _, _ in DelayedMeetingLLM() }, notify: { notices.append($0.kind) })
        processing.regenerateMinutes(recordingID: id, template: .defaultTemplate)
        #expect(processing.progress[id]?.stage == .minutes)
        await processing.waitForMinutesGeneration(recordingID: id)
        #expect(processing.progress[id]?.stage == .minutesCompleted)
        #expect(try store.fetchMinutes(recordingID: id).last?.sections.first?.body == "后台生成测试")
        #expect(try store.fetchRecording(id: id)?.title == "后台生成测试")
        #expect(notices == [.minutesStarted, .minutesCompleted])
    }
}
