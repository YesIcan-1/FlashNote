import Foundation
import AVFoundation
import FlashNoteCore

/// App 层直播转写引擎：核心协议 + 局部文本直播通道（UI 实时高亮用）。
protocol LiveTranscriptionEngine: TranscriptionEngine {
    /// 局部（未定稿）文本：nil 表示当前无局部文本。
    var onPartialText: ((String?) -> Void)? { get set }
    /// 向识别器推送音频缓冲（由 AudioService 调用）。
    func append(_ buffer: AVAudioPCMBuffer)
    /// 停止录音前把识别器已返回、但尚未标记为 final 的文字写入最终段落。
    func finalizePending()
}

extension LiveTranscriptionEngine {
    func finalizePending() {}
}
