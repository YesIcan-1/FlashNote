import Foundation
import Testing
@testable import FlashNoteCore

struct MinutesTemplateTests {
    @Test func builtinsExist() {
        let builtins = MinutesTemplate.builtins
        #expect(builtins.count == 6)
        let names = builtins.map(\.name)
        #expect(names.contains("工作纪要"))
        #expect(names.contains("会议纪要"))
        #expect(names.contains("课程纪要"))
    }

    @Test func meetingTemplateMatchesDetailedMinutesLayout() {
        let meeting = MinutesTemplate.defaultTemplate
        #expect(meeting.sections == ["会议主题", "内容总结", "会议信息", "会议议题", "会议结论", "待办"])
        #expect(meeting.userPromptTemplate.contains("Markdown 两列表格"))
        #expect(meeting.userPromptTemplate.contains("缩进列表"))
        #expect(meeting.userPromptTemplate.contains("未提及"))
        #expect(meeting.systemPrompt.contains("不编造"))
    }

    @Test func builtinsHaveSectionsAndPrompts() {
        for template in MinutesTemplate.builtins {
            #expect(!template.sections.isEmpty, "\(template.name) 缺少分节")
            #expect(!template.systemPrompt.isEmpty)
            #expect(template.userPromptTemplate.contains("{transcript}"))
            #expect(template.isBuiltin)
        }
    }

    @Test func customTemplateCodable() throws {
        let template = MinutesTemplate(
            id: "custom-1",
            name: "面试纪要",
            isBuiltin: false,
            sections: ["候选人评估", "结论"],
            systemPrompt: "你是面试官助手。",
            userPromptTemplate: "转写如下：\n{transcript}"
        )
        let data = try JSONEncoder().encode(template)
        let decoded = try JSONDecoder().decode(MinutesTemplate.self, from: data)
        #expect(decoded == template)
    }
}
