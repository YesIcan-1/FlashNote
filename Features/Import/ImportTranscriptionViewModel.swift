import Foundation
import AVFoundation
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

    @discardableResult
    func importAndTranscribe(sourceURL: URL, title: String, onCreated: ((UUID) -> Void)? = nil) async throws -> Recording {
        try await importAndTranscribe(sourceURL: sourceURL, title: title, language: "zh", onCreated: onCreated)
    }

    /// 依次处理多个来源，避免同时调用云端转写造成顺序与资源不可控。
    func importAndTranscribe(sourceURLs: [URL], language: String = "zh") async throws {
        for sourceURL in sourceURLs {
            try await importAndTranscribe(
                sourceURL: sourceURL,
                title: sourceURL.deletingPathExtension().lastPathComponent,
                language: language
            )
        }
    }

    @discardableResult
    private func importAndTranscribe(sourceURL: URL, title: String, language: String, onCreated: ((UUID) -> Void)? = nil) async throws -> Recording {
        let id = UUID()
        let audioDir = storeDirectory.appendingPathComponent("audio", isDirectory: true)
        try FileManager.default.createDirectory(at: audioDir, withIntermediateDirectories: true)
        let ext = sourceURL.pathExtension.isEmpty ? "m4a" : sourceURL.pathExtension
        let destURL = audioDir.appendingPathComponent("\(id.uuidString).\(ext)")
        try FileManager.default.copyItem(at: sourceURL, to: destURL)

        var recording = Recording(id: id, title: title.isEmpty ? sourceURL.lastPathComponent : title)
        recording.audioFilename = destURL.lastPathComponent
        if let audio = try? AVAudioFile(forReading: destURL), audio.processingFormat.sampleRate > 0 {
            recording.duration = Double(audio.length) / audio.processingFormat.sampleRate
        }
        try store.upsertRecording(recording)
        onCreated?(id)

        if shouldFail {
            throw TranscriptionError.engineFailed("mock failure")
        }

        let segments = try await engine.transcribe(audioFileURL: destURL, language: language)
        let transcript = Transcript(recordingID: id, segments: segments, language: language)
        try store.upsertTranscript(transcript)
        recording.markTranscribed()
        try store.upsertRecording(recording)
        cachedRecordings = (try? store.fetchRecordings()) ?? []
        return recording
    }
}
