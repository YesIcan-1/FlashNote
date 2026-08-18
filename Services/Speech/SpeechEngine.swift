import Foundation
import Speech
import AVFoundation
import FlashNoteCore

/// Apple 系统转写引擎（zh-CN）。局部文本走 onPartialText（当前未定稿句）；
/// 定稿时按句切分走 onSegment（每句一行、带真实起止时间戳，便于后续分人转写）。
final class SpeechEngine: LiveTranscriptionEngine {
    let displayName = "Apple 系统转写"
    let isRealtime = true

    var onSegment: ((TranscriptSegment) -> Void)?
    var onError: ((Error) -> Void)?
    var onPartialText: ((String?) -> Void)?

    private let recognizer: SFSpeechRecognizer
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var started = false
    /// 已发出句子的结束时间戳，用于去重（跨 partial→final 与多段定稿）。
    private var lastEmittedEnd: TimeInterval = 0

    /// 初始化失败（识别器不可用）时返回 nil。
    init?(locale: Locale = Locale(identifier: "zh-CN")) {
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            return nil
        }
        self.recognizer = recognizer
    }

    func start() throws {
        guard !started else { throw TranscriptionError.invalidState("already started") }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        self.request = request
        lastEmittedEnd = 0

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let result {
                let transcription = result.bestTranscription
                if result.isFinal {
                    // 分句分行：逐句发出新增句子（按结束时间戳去重）
                    for segment in transcription.segments {
                        let end = segment.timestamp + segment.duration
                        guard end > self.lastEmittedEnd else { continue }
                        let text = segment.substring.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !text.isEmpty {
                            self.onSegment?(TranscriptSegment(
                                startTime: segment.timestamp,
                                endTime: end,
                                text: text,
                                isFinal: true
                            ))
                        }
                        self.lastEmittedEnd = max(self.lastEmittedEnd, end)
                    }
                    self.onPartialText?(nil)
                } else {
                    // 局部：只显示当前未定稿的最后一句（供 UI 高亮）
                    let current = transcription.segments.last?.substring
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    self.onPartialText?((current?.isEmpty == false) ? current : nil)
                }
            }
            if let error, (error as NSError).code != 216 { // 216 = 用户取消
                self.onError?(TranscriptionError.engineFailed(error.localizedDescription))
            }
        }
        started = true
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        request?.append(buffer)
    }

    func cancel() {
        task?.cancel()
        task = nil
        request = nil
        started = false
        lastEmittedEnd = 0
        onPartialText?(nil)
    }
}
