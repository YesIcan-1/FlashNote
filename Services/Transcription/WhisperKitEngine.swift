import Foundation
import FlashNoteCore

/// 本地 WhisperKit 引擎（离线）。
///
/// 注：WhisperKit 远程包依赖尚未接入（需要稳定的 GitHub 网络以克隆仓库并下载模型，
/// 当前环境网络不可达）。此引擎作为占位：`isAvailable` 恒为 false，选择后转写会
/// 报「本地转写暂不可用」。待网络恢复后集成 WhisperKit 并替换本实现。
final class WhisperKitEngine: FileTranscriptionEngine {
    let displayName = "本地 WhisperKit"

    var isAvailable: Bool { false }

    func transcribe(audioFileURL: URL, language: String) async throws -> [TranscriptSegment] {
        throw TranscriptionError.engineUnavailable
    }
}
