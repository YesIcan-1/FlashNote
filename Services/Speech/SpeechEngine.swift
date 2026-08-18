import Foundation
import Speech
import AVFoundation
import FlashNoteCore

/// Apple 系统转写引擎（zh-CN）。局部文本走 onPartialText；定稿段落走 onSegment。
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

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let result {
                if result.isFinal {
                    let text = result.bestTranscription.formattedString
                    if !text.isEmpty {
                        self.onSegment?(TranscriptSegment(startTime: 0, text: text, isFinal: true))
                    }
                    self.onPartialText?(nil)
                } else {
                    self.onPartialText?(result.bestTranscription.formattedString)
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
        onPartialText?(nil)
    }
}
