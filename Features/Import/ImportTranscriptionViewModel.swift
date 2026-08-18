import Foundation
import FlashNoteCore

/// 导入 + 转写编排：拷贝文件到容器 → 建 Recording → 转写 → 保存 Transcript。
@Observable
final class ImportTranscriptionViewModel {
    private let store: RecordingStore
    private let engine: FileTranscriptionEngine
    private let storeDirectory: URL
    private var cachedRecordings: [Recording] = []
    var shouldFail = false  // 测试用

    init(store: RecordingStore, engine: FileTranscriptionEngine, storeDirectory: URL = AppEnvironment.defaultStoreDirectory()) {
        self.store = store
        self.engine = engine
        self.storeDirectory = storeDirectory
    }

    func recordings() -> [Recording] { cachedRecordings }

    func importAndTranscribe(sourceURL: URL, title: String) async throws {
        let id = UUID()
        let audioDir = storeDirectory.appendingPathComponent("audio", isDirectory: true)
        try FileManager.default.createDirectory(at: audioDir, withIntermediateDirectories: true)
        let ext = sourceURL.pathExtension.isEmpty ? "m4a" : sourceURL.pathExtension
        let destURL = audioDir.appendingPathComponent("\(id.uuidString).\(ext)")
        try FileManager.default.copyItem(at: sourceURL, to: destURL)

        var recording = Recording(id: id, title: title.isEmpty ? sourceURL.lastPathComponent : title)
        recording.audioFilename = destURL.lastPathComponent
        try store.upsertRecording(recording)

        if shouldFail {
            throw TranscriptionError.engineFailed("mock failure")
        }

        let segments = try await engine.transcribe(audioFileURL: destURL, language: "zh")
        let transcript = Transcript(recordingID: id, segments: segments, language: "zh")
        try store.upsertTranscript(transcript)
        recording.markTranscribed()
        try store.upsertRecording(recording)
        cachedRecordings = (try? store.fetchRecordings()) ?? []
    }
}
