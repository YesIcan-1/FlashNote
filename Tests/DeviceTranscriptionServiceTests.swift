import Testing
import Foundation
import FlashNoteCore
#if os(macOS)
@testable import FlashNoteMac
#else
@testable import FlashNote
#endif

struct DeviceTranscriptionServiceTests {
    private func makeService() -> (DeviceTranscriptionService, MockBLETransport, InMemoryStore) {
        let transport = MockBLETransport()
        let device = CB08Device(transport: transport, seqGenerator: { 0 })
        let engine = MockFileEngine()
        let store = InMemoryStore()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Dev-\(UUID().uuidString)")
        let service = DeviceTranscriptionService(device: device, engine: engine, store: store, storeDirectory: root)
        return (service, transport, store)
    }

    @Test func downloadAndTranscribeSavesRecording() async throws {
        let (service, transport, store) = makeService()
        let file = CB08FileEntry(time: 5, size: 100, name: "note20260710-162938")

        let task = Task { try await service.downloadAndTranscribe(file: file, title: "设备录音") }

        // 让 requestImport 发出后，模拟设备回放
        try await Task.sleep(nanoseconds: 50_000_000)
        transport.onNotify?(frameData(type: 2, cmd: 3, params: Data(Array("note20260710-162938.wav".utf8))))
        transport.onNotify?(frameData(type: 2, cmd: 4, params: Data(Array(0..<32))))
        transport.onNotify?(frameData(type: 2, cmd: 4, params: Data(Array(32..<64))))
        transport.onNotify?(frameData(type: 2, cmd: 5, params: Data([0])))

        let transcript = try await task.value
        #expect(transcript.segments.count == 1)
        #expect(try store.fetchRecordings().count == 1)
        #expect(try store.fetchRecordings().first?.status == .transcribed)
        #expect(transcript.fullText == "第一句。")
    }

    @Test func downloadCode1RetriesNextCandidate() async throws {
        let (service, transport, store) = makeService()
        // 无扩展名 → 候选 ["note.wav", "note.opus", "note"]
        let file = CB08FileEntry(time: 5, size: 100, name: "note")

        let task = Task { try await service.downloadAndTranscribe(file: file, title: "x") }
        try await Task.sleep(nanoseconds: 50_000_000)

        // 第一次候选 .wav：code=1 不存在 → 换下一候选
        transport.onNotify?(frameData(type: 2, cmd: 5, params: Data([1])))
        try await Task.sleep(nanoseconds: 50_000_000)
        // 第二次候选 .opus：成功
        transport.onNotify?(frameData(type: 2, cmd: 3, params: Data(Array("note.opus".utf8))))
        transport.onNotify?(frameData(type: 2, cmd: 4, params: Data([9, 9])))
        transport.onNotify?(frameData(type: 2, cmd: 5, params: Data([0])))

        _ = try await task.value
        #expect(try store.fetchRecordings().count == 1)
    }

    @Test func downloadProgressUsesCompressedFileSize() async throws {
        let (service, transport, _) = makeService()
        let file = CB08FileEntry(time: 173, size: 64, name: "note")
        var reportedProgress: [Double] = []
        service.onProgress = { progress, _ in reportedProgress.append(progress) }

        let task = Task { try await service.downloadAndTranscribe(file: file, title: "note") }
        try await Task.sleep(nanoseconds: 50_000_000)
        transport.onNotify?(frameData(type: 2, cmd: 3, params: Data("note.wav".utf8)))
        transport.onNotify?(frameData(type: 2, cmd: 4, params: Data(repeating: 1, count: 32)))
        #expect(reportedProgress.contains { abs($0 - 0.5) < 0.001 })
        transport.onNotify?(frameData(type: 2, cmd: 4, params: Data(repeating: 1, count: 32)))
        transport.onNotify?(frameData(type: 2, cmd: 5, params: Data([0])))
        _ = try await task.value
    }
}
