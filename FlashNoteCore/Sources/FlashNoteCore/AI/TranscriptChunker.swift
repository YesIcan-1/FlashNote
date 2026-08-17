import Foundation

/// 把长转写文本切成适合 LLM 的块：优先在句子边界（。！？!?\n）切分，超长块做硬切。
///
/// 算法：在 maxChars 字符窗口内取最后一个句边界作为切点；窗口内无句边界
/// （单个句子超长，常见于稀疏标点的 ASR 输出）才硬切，保证每块 ≤ maxChars。
public struct TranscriptChunker {
    public var maxChars: Int

    public init(maxChars: Int = 4000) {
        precondition(maxChars > 0, "maxChars 必须为正数")
        self.maxChars = maxChars
    }

    private let breaks = CharacterSet(charactersIn: "。！？!?\n")

    public func chunk(_ text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        var chunks: [String] = []
        var start = text.startIndex

        while start < text.endIndex {
            let windowEnd = text.index(start, offsetBy: maxChars, limitedBy: text.endIndex) ?? text.endIndex
            let window = text[start..<windowEnd]
            // 切点必须位于窗口内部：窗口开头的句边界（如 "。开头"）不单独成块，
            // 而是与后续文本同块；否则会导致 "。开头" 被切成 ["。", "开头"]。
            if let lastBreak = findLastBreak(in: window), lastBreak > window.startIndex {
                let chunkEnd = text.index(after: lastBreak)
                chunks.append(String(text[start..<chunkEnd]))
                start = chunkEnd
            } else {
                chunks.append(String(window))
                start = windowEnd
            }
        }
        return chunks
    }

    private func findLastBreak(in range: Substring) -> String.Index? {
        range.lastIndex { char in
            guard let scalar = char.unicodeScalars.first else { return false }
            return breaks.contains(scalar)
        }
    }
}
