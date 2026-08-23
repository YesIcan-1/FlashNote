import Foundation
import FlashNoteCore

/// 对已保存的本地录音重新执行整段全文转写。
final class RecordingTranscriptionService {
    private let store: RecordingStore
    private let engine: FileTranscriptionEngine
    private let storeDirectory: URL

    init(store: RecordingStore, engine: FileTranscriptionEngine, storeDirectory: URL = AppEnvironment.defaultStoreDirectory()) {
        self.store = store
        self.engine = engine
        self.storeDirectory = storeDirectory
    }

    func transcribe(_ recording: Recording, language: String = "zh") async throws -> Transcript {
        guard engine.isAvailable else { throw TranscriptionError.engineUnavailable }
        guard let audioURL = RecordingAssetService.audioURL(for: recording, storeDirectory: storeDirectory),
              FileManager.default.fileExists(atPath: audioURL.path) else {
            throw TranscriptionError.engineFailed("找不到本地音频文件")
        }
        let segments = try await engine.transcribe(audioFileURL: audioURL, language: language)
        let transcript = Transcript(recordingID: recording.id, segments: segments, language: language)
        try store.upsertTranscript(transcript)
        var updated = recording
        updated.markTranscribed()
        try store.upsertRecording(updated)
        return transcript
    }
}
