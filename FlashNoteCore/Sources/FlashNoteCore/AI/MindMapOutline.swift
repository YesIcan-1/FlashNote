import Foundation

public struct MindMapNode: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let children: [MindMapNode]

    public init(id: String, title: String, children: [MindMapNode] = []) {
        self.id = id
        self.title = title
        self.children = children
    }
}

public struct MindMapOutline: Equatable, Sendable {
    public let title: String
    public let branches: [MindMapNode]

    public init(minutes: Minutes, fallbackTitle: String) {
        let topic = minutes.sections.first(where: { $0.title == "核心主题" })?.body
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        title = topic.isEmpty ? fallbackTitle : String(topic.components(separatedBy: .newlines).first ?? fallbackTitle)
        let source = minutes.sections.first(where: { $0.title == "主题结构" })?.body ?? ""
        let parsed = Self.parse(source)
        branches = parsed.isEmpty
            ? minutes.sections.filter { $0.title != "核心主题" }.enumerated().map { index, section in
                MindMapNode(id: "fallback.\(index)", title: section.title, children: Self.parse(section.body))
            }
            : parsed
    }

    private final class MutableNode {
        let title: String
        var children: [MutableNode] = []
        init(_ title: String) { self.title = title }
        func freeze(path: String) -> MindMapNode {
            MindMapNode(id: path, title: title,
                        children: children.enumerated().map { index, child in child.freeze(path: "\(path).\(index)") })
        }
    }

    private static func parse(_ markdown: String) -> [MindMapNode] {
        var roots: [MutableNode] = []
        var stack: [(level: Int, node: MutableNode)] = []
        for line in markdown.components(separatedBy: .newlines) {
            let whitespace = line.prefix { $0 == " " || $0 == "\t" }
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let text = trimmed.replacingOccurrences(of: "^(?:[-*+•]\\s+|\\d+[.)、]\\s*)", with: "", options: .regularExpression)
                .replacingOccurrences(of: "**", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            let level = whitespace.reduce(0) { $0 + ($1 == "\t" ? 2 : 1) } / 2
            while let last = stack.last, last.level >= level { stack.removeLast() }
            let node = MutableNode(text)
            if let parent = stack.last { parent.node.children.append(node) } else { roots.append(node) }
            stack.append((level, node))
        }
        return roots.enumerated().map { index, node in node.freeze(path: String(index)) }
    }
}
