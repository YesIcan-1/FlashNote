import Testing
import Foundation
import FlashNoteCore
#if os(macOS)
@testable import FlashNoteMac
#else
@testable import FlashNote
#endif

struct DeviceTranscriptionServiceTests {
    private func makeService(
        idleTimeoutNanoseconds: UInt64 = 6_000_000_000,
        engine: FileTranscriptionEngine = MockFileEngine(),
        storeDirectory: URL? = nil
    ) -> (DeviceTranscriptionService, MockBLETransport, InMemoryStore) {
        let transport = MockBLETransport()
        let device = CB08Device(transport: transport, seqGenerator: { 0 })
        let store = InMemoryStore()
        let root = storeDirectory ?? FileManager.default.temporaryDirectory.appendingPathComponent("Dev-\(UUID().uuidString)")
        let service = DeviceTranscriptionService(device: device, engine: engine, store: store, storeDirectory: root, idleTimeoutNanoseconds: idleTimeoutNanoseconds)
        return (service, transport, store)
    }

    @Test func unavailableTranscriptionKeepsDownloadedAudio() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Dev-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let unavailableEngine = MockFileEngine()
        unavailableEngine.isAvailable = false
        let (service, transport, store) = makeService(engine: unavailableEngine, storeDirectory: root)
        let task = Task {
            try await service.downloadAndTranscribe(file: .init(time: 1, size: 2, name: "note.wav"), title: "设备录音")
        }
        try await Task.sleep(nanoseconds: 50_000_000)
        transport.onNotify?(frameData(type: 2, cmd: 3, params: Data("note.wav".utf8)))
        transport.onNotify?(frameData(type: 2, cmd: 4, params: Data([1, 2])))
        transport.onNotify?(frameData(type: 2, cmd: 5, params: Data([0])))

        await #expect(throws: TranscriptionError.self) { try await task.value }
        let recording = try #require(store.fetchRecordings().first)
        #expect(recording.status == .recording)
        let filename = try #require(recording.audioFilename)
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("audio/\(filename)").path))
    }

    @Test func downloadedRecordingUsesActualNameAndAudioDuration() async throws {
        let (service, transport, store) = makeService()
        let wav = WAVEncoder.encode(samples: Array(repeating: 0, count: 16_000))
        let task = Task {
            try await service.downloadAndTranscribe(
                file: .init(time: 1, size: UInt32(wav.count), name: "note20260822-190246."),
                title: ""
            )
        }
        try await Task.sleep(nanoseconds: 50_000_000)
        transport.onNotify?(frameData(type: 2, cmd: 3, params: Data("note20260822-190246.wav".utf8)))
        for offset in stride(from: 0, to: wav.count, by: 160) {
            let end = min(offset + 160, wav.count)
            transport.onNotify?(frameData(type: 2, cmd: 4, params: wav.subdata(in: offset..<end)))
        }
        transport.onNotify?(frameData(type: 2, cmd: 5, params: Data([0])))

        _ = try await task.value
        let recording = try #require(store.fetchRecordings().first)
        #expect(recording.title == "note20260822-190246")
        #expect(abs(recording.duration - 1) < 0.01)
    }

    @Test func incompleteDownloadIsNotSavedAsTranscription() async throws {
        let (service, transport, store) = makeService(idleTimeoutNanoseconds: 20_000_000)
        let task = Task { try await service.downloadAndTranscribe(file: .init(time: 1, size: 64, name: "note"), title: "note") }
        try await Task.sleep(nanoseconds: 10_000_000)
        transport.onNotify?(frameData(type: 2, cmd: 4, params: Data(repeating: 1, count: 20)))
        await #expect(throws: DeviceError.incompleteDownload) { try await task.value }
        #expect(try store.fetchRecordings().isEmpty)
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
        // 无扩展名时优先尝试 .opus（BLE 通道小 16 倍），再回退 .wav 和原始名。
        let file = CB08FileEntry(time: 5, size: 100, name: "note")

        let task = Task { try await service.downloadAndTranscribe(file: file, title: "x") }
        try await Task.sleep(nanoseconds: 50_000_000)

        // 首选 .opus 不存在 → 回退到 .wav。
        transport.onNotify?(frameData(type: 2, cmd: 5, params: Data([1])))
        try await Task.sleep(nanoseconds: 50_000_000)
        // 第二次候选 .wav：成功（损坏数据会继续回退，故此处返回合法 WAV 名）。
        transport.onNotify?(frameData(type: 2, cmd: 3, params: Data(Array("note.wav".utf8))))
        transport.onNotify?(frameData(type: 2, cmd: 4, params: Data([9, 9])))
        transport.onNotify?(frameData(type: 2, cmd: 5, params: Data([0])))

        _ = try await task.value
        #expect(try store.fetchRecordings().count == 1)
    }

    @Test func corruptOpusFallsBackToWAVBeforeTranscription() async throws {
        let (service, transport, store) = makeService()
        let task = Task { try await service.downloadAndTranscribe(file: .init(time: 1, size: 40, name: "note"), title: "note") }
        try await Task.sleep(nanoseconds: 50_000_000)
        transport.onNotify?(frameData(type: 2, cmd: 3, params: Data("note.opus".utf8)))
        transport.onNotify?(frameData(type: 2, cmd: 4, params: Data([1, 2])))
        transport.onNotify?(frameData(type: 2, cmd: 5, params: Data([0])))
        try await Task.sleep(nanoseconds: 50_000_000)
        transport.onNotify?(frameData(type: 2, cmd: 3, params: Data("note.wav".utf8)))
        transport.onNotify?(frameData(type: 2, cmd: 4, params: Data([1, 2])))
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

    @Test func wavFallbackDoesNotUseCompressedSizeForPercentage() async throws {
        let (service, transport, _) = makeService()
        var reportedProgress: [Double] = []
        service.onProgress = { progress, _ in reportedProgress.append(progress) }
        let task = Task {
            try await service.downloadAndTranscribe(
                file: .init(time: 173, size: 64, name: "note"), title: "note"
            )
        }
        try await Task.sleep(nanoseconds: 50_000_000)
        transport.onNotify?(frameData(type: 2, cmd: 5, params: Data([1])))
        try await Task.sleep(nanoseconds: 50_000_000)
        transport.onNotify?(frameData(type: 2, cmd: 3, params: Data("note.wav".utf8)))
        transport.onNotify?(frameData(type: 2, cmd: 4, params: Data(repeating: 1, count: 160)))
        #expect(!reportedProgress.contains { $0 > 0 && $0 < 1 })
        transport.onNotify?(frameData(type: 2, cmd: 5, params: Data([0])))
        _ = try await task.value
    }

    @Test func downloadProgressDoesNotRefreshUIForEveryBLEPacket() async throws {
        let (service, transport, _) = makeService()
        var updates = 0
        service.onProgress = { _, _ in updates += 1 }
        let task = Task {
            try await service.downloadAndTranscribe(
                file: .init(time: 2, size: 1_000, name: "frequent.wav"), title: "frequent"
            )
        }
        try await Task.sleep(nanoseconds: 50_000_000)
        transport.onNotify?(frameData(type: 2, cmd: 3, params: Data("frequent.wav".utf8)))
        for _ in 0..<1_000 {
            transport.onNotify?(frameData(type: 2, cmd: 4, params: Data([1])))
        }
        transport.onNotify?(frameData(type: 2, cmd: 5, params: Data([0])))
        _ = try await task.value
        #expect(updates <= 120)
    }

    @Test func interruptedDownloadResumesFromSavedOffset() async throws {
        let (service, transport, store) = makeService(idleTimeoutNanoseconds: 20_000_000)
        let file = CB08FileEntry(time: 99, size: 40, name: "resume")
        let first = Task { try await service.downloadAndTranscribe(file: file, title: "resume") }
        try await Task.sleep(nanoseconds: 10_000_000)
        transport.onNotify?(frameData(type: 2, cmd: 4, params: Data(repeating: 1, count: 20)))
        await #expect(throws: DeviceError.incompleteDownload) { try await first.value }

        let second = Task { try await service.downloadAndTranscribe(file: file, title: "resume") }
        try await Task.sleep(nanoseconds: 10_000_000)
        var parser = CB08FrameParser()
        let request = try #require(transport.wrote.last.flatMap { parser.feed($0).first })
        #expect(request.type == 2)
        #expect(request.cmd == 2)
        let p = request.params
        let offset = UInt32(p[0]) | (UInt32(p[1]) << 8) | (UInt32(p[2]) << 16) | (UInt32(p[3]) << 24)
        #expect(offset == 20)
        transport.onNotify?(frameData(type: 2, cmd: 3, params: Data("resume.wav".utf8)))
        transport.onNotify?(frameData(type: 2, cmd: 4, params: Data(repeating: 2, count: 20)))
        transport.onNotify?(frameData(type: 2, cmd: 5, params: Data([0])))

        _ = try await second.value
        #expect(try store.fetchRecordings().count == 1)
    }
}
