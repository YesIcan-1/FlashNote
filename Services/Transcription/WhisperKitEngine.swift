import Foundation
import FlashNoteCore
import WhisperKit

/// On-device file transcription. The model is downloaded once and reused for
/// later recordings; audio remains on this device.
final class WhisperKitEngine: FileTranscriptionEngine {
    let displayName = "本地 WhisperKit"
    var isAvailable: Bool { true }
    static var defaultLocalModelRoot: URL {
        AppEnvironment.defaultStoreDirectory().appendingPathComponent("models/whisperkit")
    }

    func transcribe(audioFileURL: URL, language: String) async throws -> [TranscriptSegment] {
        let results = try await LocalWhisperRuntime.shared.transcribe(
            audioPath: audioFileURL.path, language: language
        )
        return Self.convert(results: results)
    }

    static func convert(results: [TranscriptionResult]) -> [TranscriptSegment] {
        results.flatMap { result in
            result.segments.compactMap { segment in
                let cleaned = segment.text
                    .replacingOccurrences(of: #"<\|[^<>]*\|>"#, with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !cleaned.isEmpty else { return nil }
                let text = result.language.hasPrefix("zh")
                    ? (cleaned.applyingTransform(StringTransform("Traditional-Simplified"), reverse: false) ?? cleaned)
                    : cleaned
                return TranscriptSegment(
                    startTime: TimeInterval(segment.start),
                    endTime: TimeInterval(segment.end),
                    text: text
                )
            }
        }
    }

    static func localConfiguration(at root: URL) -> WhisperKitConfig? {
        let model = root.appendingPathComponent("openai_whisper-large-v3-v20240930_626MB")
        let tokenizer = root.appendingPathComponent("tokenizer")
        let required = ["AudioEncoder", "TextDecoder", "MelSpectrogram"].map {
            model.appendingPathComponent("\($0).mlmodelc/weights/weight.bin").path
        } + [tokenizer.appendingPathComponent("tokenizer.json").path]
        guard required.allSatisfy(FileManager.default.fileExists(atPath:)) else { return nil }
        return WhisperKitConfig(
            model: "large-v3-v20240930_626MB",
            modelFolder: model.path,
            tokenizerFolder: tokenizer,
            verbose: false,
            download: false
        )
    }
}

private actor LocalWhisperRuntime {
    static let shared = LocalWhisperRuntime()
    private var pipeline: WhisperKit?
    private var loadingTask: Task<WhisperKit, Error>?

    func transcribe(audioPath: String, language: String) async throws -> [TranscriptionResult] {
        let model = try await loadedPipeline()
        let audioOptions = AudioInputOptions(audioLoadingMode: .incremental)
        let decodeOptions = DecodingOptions(task: .transcribe, language: language,
                                            skipSpecialTokens: true, concurrentWorkerCount: 4)
        return try await model.transcribe(
            audioPath: audioPath,
            audioInputOptions: audioOptions,
            decodeOptions: decodeOptions
        )
    }

    private func loadedPipeline() async throws -> WhisperKit {
        if let pipeline { return pipeline }
        if loadingTask == nil {
            loadingTask = Task {
                let config = WhisperKitEngine.localConfiguration(at: WhisperKitEngine.defaultLocalModelRoot)
                    ?? WhisperKitConfig(model: "large-v3-v20240930_626MB", verbose: false)
                return try await WhisperKit(config)
            }
        }
        do {
            let loaded = try await loadingTask!.value
            pipeline = loaded
            loadingTask = nil
            return loaded
        } catch {
            loadingTask = nil
            throw error
        }
    }
}
