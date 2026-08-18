import Foundation
import os
import AVFoundation
import FlashNoteCore

/// 录音页状态机：idle → recording ⇄ paused → idle。
/// 编排 音频采集 + 实时转写 + 本地保存；依赖协议注入，可单测。
/// 注意：授权检查不在 ViewModel 内做——由视图层在创建本对象前 async 调用
/// SpeechAuthorization.requestPermissions()（保持 start() 纯编排可测）。
@Observable
final class RecorderViewModel {
    enum Phase: Equatable {
        case idle
        case recording
        case paused
    }

    private(set) var phase: Phase = .idle
    private(set) var elapsed: TimeInterval = 0
    private(set) var level: Float = 0
    private(set) var segments: [TranscriptSegment] = []
    private(set) var partialText: String?
    private(set) var recordingID: UUID?
    private(set) var recordingTitle = "未命名录音"
    private(set) var errorMessage: String?

    private let audio: AudioRecording
    private let engine: LiveTranscriptionEngine
    private let store: RecordingStore
    private var service: TranscriptionService?
    private var timer: Timer?

    init(audio: AudioRecording, engine: LiveTranscriptionEngine, store: RecordingStore) {
        self.audio = audio
        self.engine = engine
        self.store = store
        engine.onPartialText = { [weak self] text in
            self?.partialText = text
        }
        engine.onError = { [weak self] _ in
            self?.errorMessage = "转写引擎出错，请重试"
        }
    }

    func start() throws {
        recorderLogger.info("start begin")
        guard phase == .idle else { throw TranscriptionError.invalidState("already started") }

        let id = UUID()
        recordingID = id
        service = TranscriptionService(recordingID: id, engine: engine)
        service?.onNewSegment = { [weak self] segment in
            self?.segments.append(segment)
            self?.partialText = nil
        }
        segments = []
        partialText = nil
        elapsed = 0

        let fileURL = Self.recordingFileURL(for: id)
        do {
            try audio.startRecording(to: fileURL)
            recorderLogger.info("audio started")
        } catch {
            recorderLogger.error("audio start failed: \(error)")
            phase = .idle
            throw error
        }
        try service?.begin()
        recorderLogger.info("service began")
        phase = .recording
        startTimer()
        wireAudio()
    }

    func pause() {
        guard phase == .recording else { return }
        audio.pause()
        phase = .paused
    }

    func resume() {
        guard phase == .paused else { return }
        audio.resume()
        phase = .recording
    }

    func stop() {
        guard phase != .idle else { return }
        audio.stop()
        stopTimer()
        engine.cancel()
        guard let service, let recordingID else { return }

        let transcript = service.finish()
        segments = transcript.segments
        var recording = Recording(id: recordingID, title: recordingTitle)
        recording.duration = elapsed
        recording.audioFilename = "\(recordingID.uuidString).caf"
        recording.markTranscribed()
        do {
            try store.upsertRecording(recording)
            try store.upsertTranscript(transcript)
        } catch {
            errorMessage = "保存失败：\(error.localizedDescription)"
        }
        phase = .idle
    }

    private func wireAudio() {
        audio.onLevel = { [weak self] level in
            self?.level = level
        }
        audio.onBuffer = { [weak self] buffer in
            self?.engine.append(buffer)
        }
    }

    private func startTimer() {
        timer?.invalidate()
        let start = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.elapsed = Date().timeIntervalSince(start)
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    /// 录音文件位置：Application Support/FlashNote/audio/{id}.caf
    static func recordingFileURL(for id: UUID) -> URL {
        AppEnvironment.defaultStoreDirectory()
            .appendingPathComponent("audio", isDirectory: true)
            .appendingPathComponent("\(id.uuidString).caf")
    }

    /// 秒 → "HH:MM:SS"。纯函数（可测）。
    static func formatElapsed(_ total: TimeInterval) -> String {
        let total = Int(total)
        return String(format: "%02d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }

    /// 错误 → 用户可读文案（可测）。
    static func errorText(for error: Error) -> String {
        if let transcriptionError = error as? TranscriptionError {
            switch transcriptionError {
            case .permissionDenied:
                return "需要麦克风和语音识别权限，请在系统设置中允许后重试"
            case .engineUnavailable:
                return "语音识别不可用"
            case .invalidState(let detail):
                return "状态错误：\(detail)"
            case .engineFailed(let detail):
                return "识别失败：\(detail)"
            }
        }
        return error.localizedDescription
    }
}
