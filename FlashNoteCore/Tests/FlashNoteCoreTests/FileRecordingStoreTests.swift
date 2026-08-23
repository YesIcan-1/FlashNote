import Foundation
import Testing
@testable import FlashNoteCore

final class FileRecordingStoreTests {
    private let root: URL
    private let store: FileRecordingStore

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlashNoteTests-\(UUID().uuidString)")
        store = try FileRecordingStore(root: root)
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    @Test func recordingCRUD() throws {
        let rec = Recording(title: "周会纪要")
        try store.upsertRecording(rec)
        #expect(try store.fetchRecordings() == [rec])
        #expect(try store.fetchRecording(id: rec.id) == rec)

        var updated = rec
        updated.markTranscribed()
        try store.upsertRecording(updated)
        #expect(try store.fetchRecording(id: rec.id)?.status == .transcribed)

        try store.deleteRecording(id: rec.id)
        #expect(try store.fetchRecording(id: rec.id) == nil)
        #expect(try store.fetchRecordings() == [])
    }

    @Test func storePersistsAcrossInstances() throws {
        let rec = Recording(title: "持久化")
        try store.upsertRecording(rec)
        let second = try FileRecordingStore(root: root)
        #expect(try second.fetchRecordings() == [rec])
    }

    @Test func transcriptAndMinutesRoundTrip() throws {
        let rec = Recording(title: "x")
        try store.upsertRecording(rec)
        var transcript = Transcript(recordingID: rec.id)
        transcript.append(TranscriptSegment(startTime: 0, text: "第一句。"))
        try store.upsertTranscript(transcript)
        #expect(try store.fetchTranscript(recordingID: rec.id) == transcript)

        let minutes = Minutes(
            recordingID: rec.id,
            templateID: "builtin.work",
            styleName: "工作纪要",
            sections: [MinutesSection(title: "结论", body: "通过。")],
            model: "mock"
        )
        try store.upsertMinutes(minutes)
        #expect(try store.fetchMinutes(recordingID: rec.id) == [minutes])
    }

    @Test func minutesHistoryPreserved() throws {
        // 规格 §5.4：切换风格重新生成时保留旧纪要（可回溯）——按 minutes.id 键控，同录音多份纪要并存
        let rec = Recording(title: "x")
        try store.upsertRecording(rec)
        let first = Minutes(
            recordingID: rec.id,
            templateID: "builtin.work",
            styleName: "工作纪要",
            sections: [MinutesSection(title: "结论", body: "第一版。")],
            model: "mock",
            generatedAt: Date(timeIntervalSince1970: 100)
        )
        let second = Minutes(
            recordingID: rec.id,
            templateID: "builtin.meeting",
            styleName: "会议纪要",
            sections: [MinutesSection(title: "议题", body: "第二版。")],
            model: "mock",
            generatedAt: Date(timeIntervalSince1970: 200)
        )
        try store.upsertMinutes(first)
        try store.upsertMinutes(second)
        let fetched = try store.fetchMinutes(recordingID: rec.id)
        #expect(fetched.count == 2)
        #expect(fetched.contains(first))
        #expect(fetched.contains(second))
    }

    @Test func deletingRecordingAlsoRemovesTranscriptAndMinutes() throws {
        let rec = Recording(title: "要删除的录音")
        try store.upsertRecording(rec)
        try store.upsertTranscript(Transcript(recordingID: rec.id, segments: [TranscriptSegment(startTime: 0, text: "全文")]))
        try store.upsertMinutes(Minutes(
            recordingID: rec.id,
            templateID: "builtin.work",
            styleName: "工作纪要",
            sections: [MinutesSection(title: "结论", body: "内容")],
            model: "mock"
        ))

        try store.deleteRecording(id: rec.id)

        #expect(try store.fetchRecording(id: rec.id) == nil)
        #expect(try store.fetchTranscript(recordingID: rec.id) == nil)
        #expect(try store.fetchMinutes(recordingID: rec.id).isEmpty)
    }

    @Test func folderCRUD() throws {
        let folder = Folder(name: "工作")
        try store.upsertFolder(folder)
        #expect(try store.fetchFolders() == [folder])
    }

    @Test func corruptedFileThrows() throws {
        let rec = Recording(title: "x")
        try store.upsertRecording(rec)
        try "not json".write(to: root.appendingPathComponent("recording-\(rec.id.uuidString).json"), atomically: true, encoding: .utf8)
        do {
            _ = try store.fetchRecording(id: rec.id)
            Issue.record("应当抛出错误")
        } catch {
            #expect(error as? StoreError == .corrupted("recording"))
        }
    }

    @Test func missingRecordingReturnsNil() throws {
        #expect(try store.fetchRecording(id: UUID()) == nil)
    }
}
