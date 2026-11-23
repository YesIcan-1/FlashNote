import Foundation
import Speech
import AVFoundation
import FlashNoteCore

/// Apple 系统转写引擎。临时识别文字和定稿句子由同一套规则分行。
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
    private var latestSegments: [SFTranscriptionSegment] = []
    private var latestFormattedString = ""
    private let stateLock = NSLock()

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
        request.addsPunctuation = true
        request.taskHint = .dictation
        self.request = request
        stateLock.lock()
        lastEmittedEnd = 0
        latestSegments = []
        latestFormattedString = ""
        started = true
        stateLock.unlock()

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let result {
                let transcription = result.bestTranscription
                self.stateLock.lock()
                let isActive = self.started
                if isActive {
                    self.latestSegments = transcription.segments
                    self.latestFormattedString = transcription.formattedString
                }
                self.stateLock.unlock()
                guard isActive else { return }
                if result.isFinal {
                    self.emitNewSegments(transcription.segments, formattedString: transcription.formattedString)
                    self.onPartialText?(nil)
                } else {
                    self.onPartialText?(self.pendingText(in: transcription))
                }
            }
            if let error, (error as NSError).code != 216 { // 216 = 用户取消
                self.onError?(TranscriptionError.engineFailed(error.localizedDescription))
            }
        }
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        request?.append(buffer)
    }

    func finalizePending() {
        stateLock.lock()
        let pending = latestSegments
        let formattedString = latestFormattedString
        stateLock.unlock()
        emitNewSegments(pending, formattedString: formattedString)
        onPartialText?(nil)
    }

    private func pendingText(in transcription: SFTranscription) -> String? {
        stateLock.lock()
        let emittedEnd = lastEmittedEnd
        stateLock.unlock()
        let recognized = transcription.segments
        let firstPending = recognized.firstIndex { $0.timestamp + $0.duration > emittedEnd + 0.01 }
        let current: String
        if let firstPending {
            let tokens = (firstPending..<recognized.count).map { index in
                let segment = recognized[index]
                return LiveSpeechToken(startTime: segment.timestamp,
                    endTime: segment.timestamp + segment.duration,
                    text: tokenText(at: index, in: recognized, formattedString: transcription.formattedString))
            }
            current = LiveTranscriptSegmenter.segments(tokens).map(\.text).joined(separator: "\n")
        } else {
            current = emittedEnd == 0 ? transcription.formattedString : ""
        }
        let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func emitNewSegments(_ recognized: [SFTranscriptionSegment], formattedString: String) {
        stateLock.lock()
        var tokens: [LiveSpeechToken] = []
        for (index, segment) in recognized.enumerated() {
            let end = segment.timestamp + segment.duration
            guard end > lastEmittedEnd + 0.01 else { continue }
            let text = tokenText(at: index, in: recognized, formattedString: formattedString)
            if !text.isEmpty {
                tokens.append(LiveSpeechToken(startTime: segment.timestamp, endTime: end, text: text))
            }
            lastEmittedEnd = max(lastEmittedEnd, end)
        }
        stateLock.unlock()
        for segment in LiveTranscriptSegmenter.segments(tokens) { onSegment?(segment) }
    }

    private func tokenText(at index: Int, in recognized: [SFTranscriptionSegment], formattedString: String) -> String {
        let segment = recognized[index]
        let location = segment.substringRange.location
        let nextLocation = index + 1 < recognized.count
            ? recognized[index + 1].substringRange.location : (formattedString as NSString).length
        guard location >= 0, nextLocation >= location,
              let range = Range(NSRange(location: location, length: nextLocation - location), in: formattedString) else {
            return segment.substring
        }
        let formattedToken = String(formattedString[range])
        return formattedToken.isEmpty ? segment.substring : formattedToken
    }

    func cancel() {
        stateLock.lock()
        started = false
        latestSegments = []
        latestFormattedString = ""
        lastEmittedEnd = 0
        stateLock.unlock()
        task?.cancel()
        task = nil
        request = nil
        onPartialText?(nil)
    }
}

struct LiveSpeechToken {
    let startTime: TimeInterval
    let endTime: TimeInterval
    let text: String
}

enum LiveTranscriptSegmenter {
    private static let sentenceEndings = Set("。！？!?；;")

    static func lines(_ text: String) -> [String] {
        let characters = Array(text)
        var result: [String] = []
        var current = ""
        func flush() {
            let line = current.trimmingCharacters(in: .whitespacesAndNewlines)
            if !line.isEmpty { result.append(line) }
            current = ""
        }
        for index in characters.indices {
            let character = characters[index]
            if character == "\n" || character == "\r" {
                flush()
                continue
            }
            current.append(character)
            let decimalPoint = character == "." && index > 0 && index + 1 < characters.count
                && characters[index - 1].isNumber && characters[index + 1].isNumber
            let sentenceEnd = sentenceEndings.contains(character) || (character == "." && !decimalPoint)
            if sentenceEnd { flush() }
        }
        flush()
        return result
    }

    static func segments(_ tokens: [LiveSpeechToken]) -> [TranscriptSegment] {
        var result: [TranscriptSegment] = []
        var text = ""
        var startTime: TimeInterval = 0
        var endTime: TimeInterval = 0
        func flush() {
            for line in lines(text) {
                result.append(TranscriptSegment(startTime: startTime, endTime: endTime, text: line))
            }
            text = ""
        }
        for token in tokens {
            if !text.isEmpty && token.startTime - endTime >= 0.45 { flush() }
            if text.isEmpty { startTime = token.startTime }
            text += token.text
            endTime = token.endTime
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if let last = trimmed.last,
               sentenceEndings.contains(last) || last == "." {
                flush()
            }
        }
        flush()
        return result
    }
}
