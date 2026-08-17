import Foundation

/// 把长转写文本切成适合 LLM 的块：优先在句子边界（。！？!?\n）切分，超长块做硬切。
public struct TranscriptChunker {
    public var maxChars: Int

    public init(maxChars: Int = 4000) {
        self.maxChars = maxChars
    }

    private let breaks = CharacterSet(charactersIn: "。！？!?\n")

    public func chunk(_ text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        var chunks: [String] = []
        var current = ""
        var buffer = ""

        for char in text {
            buffer.append(char)
            guard let scalar = char.unicodeScalars.first, breaks.contains(scalar) else { continue }
            if !current.isEmpty && current.count + buffer.count > maxChars {
                chunks.append(current)
                current = ""
            }
            current += buffer
            buffer = ""
        }
        current += buffer

        while current.count > maxChars {
            let cut = current.index(current.startIndex, offsetBy: maxChars)
            chunks.append(String(current[..<cut]))
            current = String(current[cut...])
        }
        if !current.isEmpty {
            chunks.append(current)
        }
        return chunks
    }
}
