import Foundation
import FlashNoteCore

/// 根据设置构造转写引擎。
enum FileTranscriptionEngineFactory {
    static func make(settings: AppSettings) -> FileTranscriptionEngine {
        switch settings.transcriptionEngine {
        case .cloudWhisper:
            CloudWhisperEngine(settings: settings)
        case .whisperKit:
            WhisperKitEngine()
        }
    }
}
