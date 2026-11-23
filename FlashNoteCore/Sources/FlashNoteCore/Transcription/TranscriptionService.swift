import Foundation

/// 编排单个引擎：把引擎回调的段落累积进 Transcript，并对回调做线程安全保护。
///
/// 段落契约（防止流式引擎 partial→final 重复文本）：
/// 本服务只追加 `isFinal == true` 的段落；非最终段（`isFinal == false`）由
/// App 层引擎实现自行聚合（如用相同 startTime 替换临时段），仅在确定时
/// 以 `isFinal == true` 回调。Mock 引擎（本包测试）直接回调最终段落。
///
/// 线程安全：所有状态（_transcript / _lastError）的读写都在 lock 保护下进行；
/// 引擎回调可来自任意队列。调用方应在调用 finish() 前先停止引擎，
/// 确保没有回调在途（晚到的段落不会进入已返回的快照）。
public final class TranscriptionService {
    private var _transcript: Transcript
    private var _lastError: Error?

    private let engine: TranscriptionEngine
    private let lock = NSLock()

    /// 每追加一个最终段落时回调（在锁内触发，调用方勿在回调中调用本服务方法以免死锁）。
    /// App 层用它做实时 UI 更新（如"最新一段高亮"）。
    public var onNewSegment: ((TranscriptSegment) -> Void)?
    public var onEngineError: ((Error) -> Void)?

    public init(recordingID: UUID, engine: TranscriptionEngine, language: String = "zh-Hans") {
        self._transcript = Transcript(recordingID: recordingID, language: language)
        self.engine = engine
        engine.onSegment = { [weak self] segment in
            guard let self, segment.isFinal else { return }
            self.lock.lock()
            self._transcript.append(segment)
            let onNew = self.onNewSegment
            self.lock.unlock()
            onNew?(segment)
        }
        engine.onError = { [weak self] error in
            self?.setLastError(error)
        }
    }

    public var transcript: Transcript {
        lock.lock(); defer { lock.unlock() }
        return _transcript
    }

    public var lastError: Error? {
        lock.lock(); defer { lock.unlock() }
        return _lastError
    }

    public func begin() throws {
        do {
            try engine.start()
        } catch {
            setLastError(error)
            throw error
        }
    }

    public func cancel() {
        engine.cancel()
    }

    /// 结束转写，返回最终 Transcript 快照。
    public func finish() -> Transcript {
        transcript
    }

    private func setLastError(_ error: Error) {
        lock.lock()
        _lastError = error
        let onEngineError = onEngineError
        lock.unlock()
        onEngineError?(error)
    }
}
