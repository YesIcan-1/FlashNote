import Testing
@testable import FlashNoteCore

struct TranscriptChunkerTests {
    @Test func emptyText() {
        #expect(TranscriptChunker().chunk("") == [])
    }

    @Test func shortTextSingleChunk() {
        let text = "第一句。第二句！第三句？"
        #expect(TranscriptChunker(maxChars: 100).chunk(text) == [text])
    }

    @Test func longTextSplitsAtSentenceBoundaries() {
        var text = ""
        for i in 0..<50 {
            text += "第\(i)句是一段完整的话。"
        }
        let chunks = TranscriptChunker(maxChars: 100).chunk(text)
        #expect(chunks.count > 1)
        for chunk in chunks {
            #expect(chunk.count <= 100)
            #expect(chunk.hasSuffix("。") || chunk.hasSuffix("！") || chunk.hasSuffix("？"))
        }
        #expect(chunks.joined() == text)
    }

    @Test func noSeparatorHardSplit() {
        let text = String(repeating: "啊", count: 250)
        let chunks = TranscriptChunker(maxChars: 100).chunk(text)
        #expect(chunks.count == 3)
        for chunk in chunks {
            #expect(chunk.count <= 100)
        }
        #expect(chunks.joined() == text)
    }

    @Test func newlineIsBreak() {
        let text = "第一行\n第二行\n第三行"
        let chunks = TranscriptChunker(maxChars: 8).chunk(text)
        #expect(chunks.count > 1)
        #expect(chunks.joined() == text)
    }

    @Test func midTextOversizedSentenceHardSplit() {
        // 句中超长句子（无标点）必须被硬切，块数 = 3、每块 ≤ maxChars
        let text = "短句。" + String(repeating: "长", count: 150) + "。" + "尾句。"
        let chunks = TranscriptChunker(maxChars: 100).chunk(text)
        #expect(chunks.count == 3)
        for chunk in chunks {
            #expect(chunk.count <= 100)
        }
        #expect(chunks.joined() == text)
    }

    @Test func exactMaxCharsBoundary() {
        // 恰好 maxChars 字符（末位为句号）→ 单个块
        let text = String(repeating: "字", count: 99) + "。"
        let chunks = TranscriptChunker(maxChars: 100).chunk(text)
        #expect(chunks == [text])
    }

    @Test func leadingBreakAndConsecutiveBreaks() {
        #expect(TranscriptChunker().chunk("。开头") == ["。开头"])
        #expect(TranscriptChunker().chunk("。。。") == ["。。。"])
    }
}
