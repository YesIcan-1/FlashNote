import Foundation

public struct RecordingTodo: Equatable, Sendable {
    public var title: String
    public var isCompleted: Bool

    public init(title: String, isCompleted: Bool = false) {
        self.title = title
        self.isCompleted = isCompleted
    }
}

public enum RecordingContent {
    public static func transcriptText(_ transcript: Transcript) -> String {
        transcript.segments.map { segment in
            let seconds = max(0, Int(segment.startTime))
            let stamp = String(format: "%02d:%02d", seconds / 60, seconds % 60)
            let speaker = segment.speaker.map { " \($0)" } ?? ""
            return "[\(stamp)]\(speaker) \(segment.text)"
        }.joined(separator: "\n\n")
    }

    public static func minutesMarkdown(_ minutes: Minutes) -> String {
        (["# \(minutes.styleName)"] + minutes.sections.map { "## \($0.title)\n\($0.body)" })
            .joined(separator: "\n\n") + "\n"
    }

    public static func todos(from minutes: Minutes) -> [String] {
        todoItems(from: minutes).map(\.title)
    }

    public static func todoItems(from minutes: Minutes) -> [RecordingTodo] {
        guard let section = minutes.sections.first(where: { $0.title == "待办" }) else { return [] }
        return section.body.components(separatedBy: .newlines)
            .compactMap { line in
                let withoutBullet = line.replacingOccurrences(of: #"^\s*(?:[-*•]|\d+[.、)])\s*"#, with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let isCompleted = withoutBullet.range(of: #"^\[[xX]\]\s*"#, options: .regularExpression) != nil
                let title = withoutBullet.replacingOccurrences(of: #"^\[[ xX]\]\s*"#, with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !title.isEmpty && title != "未明确" && title != "无" && title != "未提及" else { return nil }
                return RecordingTodo(title: title, isCompleted: isCompleted)
            }
    }

    public static func updatingTodos(_ todos: [String], in minutes: Minutes) -> Minutes {
        updatingTodoItems(todos.map { RecordingTodo(title: $0) }, in: minutes, includeCheckboxes: false)
    }

    public static func updatingTodoItems(_ todos: [RecordingTodo], in minutes: Minutes) -> Minutes {
        updatingTodoItems(todos, in: minutes, includeCheckboxes: true)
    }

    private static func updatingTodoItems(_ todos: [RecordingTodo], in minutes: Minutes, includeCheckboxes: Bool) -> Minutes {
        var updated = minutes
        let content = todos.map { RecordingTodo(title: $0.title.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines), isCompleted: $0.isCompleted) }
            .filter { !$0.title.isEmpty }
            .map { includeCheckboxes ? "- [\($0.isCompleted ? "x" : " ")] \($0.title)" : "- \($0.title)" }
            .joined(separator: "\n")
        let body = content.isEmpty ? "未明确" : content
        if let index = updated.sections.firstIndex(where: { $0.title == "待办" }) {
            updated.sections[index].body = body
        } else {
            updated.sections.append(MinutesSection(title: "待办", body: body))
        }
        return updated
    }
}
