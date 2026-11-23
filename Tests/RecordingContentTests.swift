import Foundation
import Testing
import FlashNoteCore

struct RecordingContentTests {
    @Test func exportsTranscriptWithTimestampsAndMinutesAsMarkdown() {
        let id = UUID()
        let transcript = Transcript(recordingID: id, segments: [
            TranscriptSegment(startTime: 0, text: "开始讨论"),
            TranscriptSegment(startTime: 65, speaker: "发言人 2", text: "确认计划")
        ])
        #expect(RecordingContent.transcriptText(transcript).contains("[01:05] 发言人 2 确认计划"))
        let minutes = Minutes(recordingID: id, templateID: "builtin.meeting", styleName: "会议纪要",
                              sections: [MinutesSection(title: "决议", body: "**确认计划**")], model: "test")
        #expect(RecordingContent.minutesMarkdown(minutes) == "# 会议纪要\n\n## 决议\n**确认计划**\n")
    }

    @Test func todoEditsPreserveOtherMinutesSections() {
        let minutes = Minutes(recordingID: UUID(), templateID: "builtin.meeting", styleName: "会议纪要",
                              sections: [MinutesSection(title: "讨论要点", body: "讨论方案"),
                                         MinutesSection(title: "待办", body: "- 联系供应商\n2. 完成评审")], model: "test")
        #expect(RecordingContent.todos(from: minutes) == ["联系供应商", "完成评审"])
        let updated = RecordingContent.updatingTodos(["修改任务", " 新任务 "], in: minutes)
        #expect(updated.sections[0].body == "讨论方案")
        #expect(updated.sections[1].body == "- 修改任务\n- 新任务")
    }

    @Test func todoCheckboxesRoundTripWithoutLosingTitles() {
        let minutes = Minutes(recordingID: UUID(), templateID: "builtin.meeting", styleName: "会议纪要",
                              sections: [MinutesSection(title: "待办", body: "- [ ] 联系供应商\n- [x] 完成评审")], model: "test")
        #expect(RecordingContent.todoItems(from: minutes) == [
            RecordingTodo(title: "联系供应商", isCompleted: false),
            RecordingTodo(title: "完成评审", isCompleted: true)
        ])
        #expect(RecordingContent.todos(from: minutes) == ["联系供应商", "完成评审"])
        let updated = RecordingContent.updatingTodoItems([
            RecordingTodo(title: " 新任务\n说明 ", isCompleted: false),
            RecordingTodo(title: "已完成", isCompleted: true)
        ], in: minutes)
        #expect(updated.sections[0].body == "- [ ] 新任务 说明\n- [x] 已完成")
    }
}
