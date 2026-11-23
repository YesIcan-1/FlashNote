import Foundation
import FlashNoteCore

/// App 层整段（文件）转写引擎抽象。
protocol FileTranscriptionEngine {
    var displayName: String { get }
    var isAvailable: Bool { get }
    /// 转写音频文件，返回分句段落（带时间戳）。
    func transcribe(audioFileURL: URL, language: String) async throws -> [TranscriptSegment]
}
