import Foundation
import FlashNoteCore

/// 云端 Whisper API 转写引擎（复用核心 OpenAIWhisperClient）。
final class CloudWhisperEngine: FileTranscriptionEngine {
    let displayName = "云端 Whisper API"
    private let settings: AppSettings

    init(settings: AppSettings) {
        self.settings = settings
    }

    var isAvailable: Bool {
        !settings.llmAPIKey.isEmpty && URL(string: settings.llmBaseURL) != nil
    }

    func transcribe(audioFileURL: URL, language: String) async throws -> [TranscriptSegment] {
        let data = try Data(contentsOf: audioFileURL)
        let client = OpenAIWhisperClient(
            baseURL: URL(string: settings.llmBaseURL)!,
            apiKey: settings.llmAPIKey,
            model: "whisper-1"
        )
        return try await client.transcribe(audioData: data, filename: audioFileURL.lastPathComponent, language: language)
    }
}
