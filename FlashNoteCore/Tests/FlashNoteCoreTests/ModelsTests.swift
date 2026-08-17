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
        var rec = Recording(title: "x")
        rec.markTranscribed()
        #expect(rec.status == .transcribed)
        #expect(rec.updatedAt >= rec.createdAt)
    }

    @Test func markSummarized() {
        var rec = Recording(title: "x")
        rec.markSummarized()
        #expect(rec.status == .summarized)
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
}
