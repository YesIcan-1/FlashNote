import Testing
import Foundation
import FlashNoteCore
#if os(macOS)
@testable import FlashNoteMac
#else
@testable import FlashNote
#endif

final class MockFileEngine: FileTranscriptionEngine {
    let displayName = "Mock"
    var isAvailable = true
    var segments: [TranscriptSegment] = [TranscriptSegment(startTime: 0, endTime: 1, text: "第一句。", isFinal: true)]
    func transcribe(audioFileURL: URL, language: String) async throws -> [TranscriptSegment] { segments }
}

struct ImportTranscriptionViewModelTests {
    private func makeVM(store: InMemoryStore = InMemoryStore(), engine: FileTranscriptionEngine = MockFileEngine()) -> (ImportTranscriptionViewModel, InMemoryStore) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Import-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let vm = ImportTranscriptionViewModel(store: store, engine: engine, storeDirectory: root)
        return (vm, store)
    }

    @Test func importAndTranscribeSavesRecording() async throws {
        let store = InMemoryStore()
        let (vm, _) = makeVM(store: store)
        let sourceURL = FileManager.default.temporaryDirectory.appendingPathComponent("src.m4a")
        try Data([1, 2, 3]).write(to: sourceURL)
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        try await vm.importAndTranscribe(sourceURL: sourceURL, title: "测试录音")
        #expect(vm.recordings().count == 1)
        let rec = try #require(vm.recordings().first)
        #expect(rec.status == .transcribed)
        let transcript = try store.fetchTranscript(recordingID: rec.id)
        #expect(transcript?.segments.count == 1)
        #expect(transcript?.fullText == "第一句。")
    }

    @Test func transcribeFailureKeepsRecordingAsRecording() async throws {
        let store = InMemoryStore()
        let (vm, _) = makeVM(store: store)
        vm.shouldFail = true
        let sourceURL = FileManager.default.temporaryDirectory.appendingPathComponent("src.m4a")
        try Data([1]).write(to: sourceURL)
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        do {
            try await vm.importAndTranscribe(sourceURL: sourceURL, title: "x")
            Issue.record("应当抛错")
        } catch { /* 预期 */ }
        #expect(try store.fetchRecordings().count == 1)
        #expect(try store.fetchRecordings().first?.status == .recording)
    }
}
