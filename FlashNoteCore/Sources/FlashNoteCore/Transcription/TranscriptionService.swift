import Foundation

/// 编排单个引擎：把引擎回调的段落累积进 Transcript，并对回调做线程安全保护。
///
/// 段落契约（防止流式引擎 partial→final 重复文本）：
/// 本服务只追加 `isFinal == true` 的段落；非最终段（`isFinal == false`）由
/// App 层引擎实现自行聚合（如用相同 startTime 替换临时段），仅在确定时
/// 以 `isFinal == true` 回调。Mock 引擎（本包测试）直接回调最终段落。
public final class TranscriptionService {
    public private(set) var transcript: Transcript
    public private(set) var lastError: Error?

    private let engine: TranscriptionEngine
    private let lock = NSLock()

    public init(recordingID: UUID, engine: TranscriptionEngine, language: String = "zh-Hans") {
        self.transcript = Transcript(recordingID: recordingID, language: language)
        self.engine = engine
        engine.onSegment = { [weak self] segment in
            guard let self, segment.isFinal else { return }
            self.lock.lock()
            self.transcript.append(segment)
            self.lock.unlock()
        }
        engine.onError = { [weak self] error in
            self?.lastError = error
        }
    }

    public func begin() throws {
        try engine.start()
    }

    public func cancel() {
        engine.cancel()
    }

    /// 结束转写，返回最终 Transcript。
    public func finish() -> Transcript {
        transcript
    }
}
