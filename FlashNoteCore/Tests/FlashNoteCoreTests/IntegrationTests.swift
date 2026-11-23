import Foundation
import Testing
@testable import FlashNoteCore

struct IntegrationTests {
    @Test func fullPipeline() async throws {
        // 1) 录音 → 转写服务（Mock 引擎）
        let recordingID = UUID()
        let engine = MockTranscriptionEngine()
        let service = TranscriptionService(recordingID: recordingID, engine: engine)
        try service.begin()
        let transcript = service.finish()
        #expect(!transcript.fullText.isEmpty)

        // 2) 纪要生成（Mock LLM）
        let client = MockLLMClient()
        client.onComplete = { _ in
            """
            ## 结论
            通过了可插拔转写架构。

            ## 行动项
            - 张伟：完成接口定义

            ## 待跟进
            下周评审。
            """
        }
        let minutes = try await MinutesGenerator(client: client).generate(
            transcript: transcript.fullText,
            template: MinutesTemplate.builtins.first { $0.id == "builtin.work" }!,
            recordingID: recordingID
        )
        #expect(minutes.sections.count == 3)

        // 3) 存储往返
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlashNoteIntegration-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try FileRecordingStore(root: root)
        var rec = Recording(id: recordingID, title: "周会纪要")
        rec.markTranscribed()
        rec.markSummarized()
        try store.upsertRecording(rec)
        try store.upsertTranscript(transcript)
        try store.upsertMinutes(minutes)

        let loadedRec = try store.fetchRecording(id: recordingID)
        let loadedTranscript = try store.fetchTranscript(recordingID: recordingID)
        let loadedMinutes = try store.fetchMinutes(recordingID: recordingID)
        #expect(loadedRec == rec)
        #expect(loadedTranscript == transcript)
        #expect(loadedMinutes == [minutes])
    }
}
