import Foundation
import Testing
@testable import FlashNoteCore

struct ModelsTests {
    @Test func recordingDefaults() {
        let rec = Recording(title: "周会纪要")
        #expect(rec.status == .recording)
        #expect(rec.duration == 0)
        #expect(rec.folderID == nil)
        #expect(rec.audioFilename == nil)
        #expect(rec.title == "周会纪要")
        #expect(rec.updatedAt == rec.createdAt)
    }

    @Test func markTranscribed() {
        var rec = Recording(title: "x", createdAt: Date(timeIntervalSince1970: 1000))
        rec.markTranscribed()
        #expect(rec.status == .transcribed)
        #expect(rec.updatedAt > rec.createdAt)
    }

    @Test func markSummarized() {
        var rec = Recording(title: "x", createdAt: Date(timeIntervalSince1970: 1000))
        rec.markSummarized()
        #expect(rec.status == .summarized)
        #expect(rec.updatedAt > rec.createdAt)
    }

    @Test func recordingCodableRoundTrip() throws {
        let rec = Recording(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            title: "测试",
            folderID: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            audioFilename: "abc.m4a",
            duration: 65.5,
            status: .transcribed,
            createdAt: Date(timeIntervalSince1970: 1000),
            updatedAt: Date(timeIntervalSince1970: 2000)
        )
        let data = try JSONEncoder().encode(rec)
        let decoded = try JSONDecoder().decode(Recording.self, from: data)
        #expect(decoded == rec)
    }

    @Test func segmentCodable() throws {
        let seg = TranscriptSegment(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
            startTime: 12.5,
            endTime: 15.0,
            speaker: "李娜",
            text: "纪要模板建议做成可自定义的。",
            isFinal: true
        )
        let data = try JSONEncoder().encode(seg)
        let decoded = try JSONDecoder().decode(TranscriptSegment.self, from: data)
        #expect(decoded == seg)
    }

    @Test func transcriptAppendAndFullText() {
        var t = Transcript(recordingID: UUID(), language: "zh-Hans")
        #expect(t.fullText == "")
        t.append(TranscriptSegment(startTime: 0, text: "第一句。"))
        t.append(TranscriptSegment(startTime: 2, text: "第二句。"))
        #expect(t.segments.count == 2)
        #expect(t.fullText == "第一句。\n第二句。")
        #expect(t.language == "zh-Hans")
    }
}
