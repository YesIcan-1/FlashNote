import Foundation
import Testing
@testable import FlashNoteCore

struct MinutesTemplateTests {
    @Test func builtinsExist() {
        let builtins = MinutesTemplate.builtins
        #expect(builtins.count == 3)
        let names = builtins.map(\.name)
        #expect(names.contains("工作纪要"))
        #expect(names.contains("会议纪要"))
        #expect(names.contains("课程纪要"))
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
