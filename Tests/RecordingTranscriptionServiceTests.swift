import Testing
import Foundation
import FlashNoteCore
#if os(macOS)
@testable import FlashNoteMac
#else
@testable import FlashNote
#endif

struct RecordingTranscriptionServiceTests {
    @Test func retranscriptionReplacesTranscriptAndUpdatesStatus() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Retry-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = InMemoryStore()
        let audioDir = root.appendingPathComponent("audio")
        try FileManager.default.createDirectory(at: audioDir, withIntermediateDirectories: true)
        let recording = Recording(title: "可重试", audioFilename: "sample.wav")
        try Data([1, 2, 3]).write(to: audioDir.appendingPathComponent("sample.wav"))
        try store.upsertRecording(recording)
        let service = RecordingTranscriptionService(store: store, engine: MockFileEngine(), storeDirectory: root)

        let transcript = try await service.transcribe(recording)

        #expect(transcript.fullText == "第一句。")
        #expect(try store.fetchRecording(id: recording.id)?.status == .transcribed)
        #expect(try store.fetchTranscript(recordingID: recording.id) == transcript)
    }
}
