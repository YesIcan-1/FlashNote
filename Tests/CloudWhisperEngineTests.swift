import Testing
import Foundation
import FlashNoteCore
import WhisperKit
#if os(macOS)
@testable import FlashNoteMac
#else
@testable import FlashNote
#endif

struct CloudWhisperEngineTests {
    private func settings(key: String?) -> AppSettings {
        let s = AppSettings(storeDirectory: URL(fileURLWithPath: "/tmp"), keychain: MockKeychain(),
                            defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!)
        if let key { s.llmAPIKey = key }
        return s
    }

    @Test func engineIsAvailableWhenKeyPresent() {
        #expect(CloudWhisperEngine(settings: settings(key: "k")).isAvailable)
    }

    @Test func engineUnavailableWithoutKey() {
        #expect(!CloudWhisperEngine(settings: settings(key: nil)).isAvailable)
    }
}

struct LocalWhisperKitEngineTests {
    @Test func localEngineCanBeSelectedWithoutCloudCredentials() {
        #expect(WhisperKitEngine().isAvailable)
    }

    @Test func mapsTimestampedWhisperSegmentsIntoAppTranscript() {
        let result = TranscriptionResult(
            text: "记者九年的底气",
            segments: [.init(start: 1.25, end: 2.5, text: "<|startoftranscript|><|zh|><|transcribe|><|1.25|> 記者九年的底氣 <|2.50|>")],
            language: "zh",
            timings: .init()
        )
        let segments = WhisperKitEngine.convert(results: [result])
        #expect(segments.count == 1)
        #expect(segments[0].text == "记者九年的底气")
        #expect(segments[0].startTime == 1.25)
        #expect(segments[0].endTime == 2.5)
    }

    @Test func usesCompleteLocalModelWhenPresent() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = root.appendingPathComponent("openai_whisper-large-v3-v20240930_626MB")
        for component in ["AudioEncoder", "TextDecoder", "MelSpectrogram"] {
            let weight = model.appendingPathComponent("\(component).mlmodelc/weights/weight.bin")
            try FileManager.default.createDirectory(at: weight.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data().write(to: weight)
        }
        let tokenizer = root.appendingPathComponent("tokenizer/tokenizer.json")
        try FileManager.default.createDirectory(at: tokenizer.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: tokenizer)

        let config = WhisperKitEngine.localConfiguration(at: root)
        #expect(config?.modelFolder == model.path)
        #expect(config?.tokenizerFolder == tokenizer.deletingLastPathComponent())
        #expect(config?.download == false)
    }

    #if os(macOS)
    @Test(.enabled(if: WhisperKitEngine.localConfiguration(at: WhisperKitEngine.defaultLocalModelRoot) != nil))
    func transcribesChineseSpeechWithInstalledModel() async throws {
        let sample = FileManager.default.temporaryDirectory.appendingPathComponent("flashnote-asr-\(UUID().uuidString).aiff")
        defer { try? FileManager.default.removeItem(at: sample) }
        let speech = Process()
        speech.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        speech.arguments = ["-v", "Tingting", "-o", sample.path, "今天我们测试本地语音识别。"]
        try speech.run()
        speech.waitUntilExit()
        #expect(speech.terminationStatus == 0)

        let segments = try await WhisperKitEngine().transcribe(audioFileURL: sample, language: "zh")
        #expect(segments.contains { $0.text.contains("测试") })
    }
    #endif
}
