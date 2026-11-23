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
    private(set) var recordedBytes: Int64 = 0
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
    private let now: () -> Date
    private var activeStartedAt: Date?
    private var completedDuration: TimeInterval = 0

    init(audio: AudioRecording, engine: LiveTranscriptionEngine, store: RecordingStore, now: @escaping () -> Date = Date.init) {
        self.audio = audio
        self.engine = engine
        self.store = store
        self.now = now
        engine.onPartialText = { [weak self] text in
            self?.updateOnMain { self?.partialText = text }
        }
    }

    func start() throws {
        recorderLogger.info("start begin")
        guard phase == .idle else { throw TranscriptionError.invalidState("already started") }

        let id = UUID()
        recordingID = id
        recordingTitle = Self.hardwareStyleTitle(at: now())
        service = TranscriptionService(recordingID: id, engine: engine)
        service?.onNewSegment = { [weak self] segment in
            self?.updateOnMain {
                self?.segments.append(segment)
                self?.partialText = nil
            }
        }
        service?.onEngineError = { [weak self] _ in
            self?.updateOnMain { self?.errorMessage = "转写引擎出错，请重试" }
        }
        segments = []
        partialText = nil
        elapsed = 0
        recordedBytes = 0
        completedDuration = 0
        activeStartedAt = nil

        let fileURL = Self.recordingFileURL(for: id)
        do {
            try audio.startRecording(to: fileURL)
            recorderLogger.info("audio started")
        } catch {
            recorderLogger.error("audio start failed: \(error)")
            phase = .idle
            throw error
        }
        do {
            try service?.begin()
        } catch {
            audio.stop()
            engine.cancel()
            try? FileManager.default.removeItem(at: fileURL)
            service = nil
            recordingID = nil
            throw error
        }
        recorderLogger.info("service began")
        phase = .recording
        activeStartedAt = now()
        startTimer()
        wireAudio()
    }

    static func hardwareStyleTitle(at date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "'note'yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }

    func pause() {
        guard phase == .recording else { return }
        refreshElapsed()
        completedDuration = elapsed
        activeStartedAt = nil
        audio.pause()
        phase = .paused
    }

    func resume() {
        guard phase == .paused else { return }
        audio.resume()
        activeStartedAt = now()
        phase = .recording
    }

    func stop() {
        guard phase != .idle else { return }
        refreshElapsed()
        audio.stop()
        stopTimer()
        let visiblePartial = partialText?.trimmingCharacters(in: .whitespacesAndNewlines)
        engine.finalizePending()
        engine.cancel()
        guard let service, let recordingID else { return }

        var transcript = service.finish()
        // 系统识别器有时仅给出可见的临时文字，不提供任何分段；停止时仍须保存这些文字。
        if transcript.segments.isEmpty, let visiblePartial, !visiblePartial.isEmpty {
            let readableText = LiveTranscriptSegmenter.lines(visiblePartial).joined(separator: "\n")
            transcript.append(TranscriptSegment(startTime: 0, endTime: elapsed, text: readableText))
        }
        segments = transcript.segments
        var recording = Recording(id: recordingID, title: recordingTitle)
        recording.duration = elapsed
        recording.audioFilename = "\(recordingID.uuidString).m4a"
        if !transcript.fullText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            recording.markTranscribed()
        }
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
            DispatchQueue.main.async { self?.level = level }
        }
        audio.onBuffer = { [weak self] buffer in
            self?.engine.append(buffer)
        }
    }

    private func updateOnMain(_ update: () -> Void) {
        if Thread.isMainThread { update() }
        else { DispatchQueue.main.sync(execute: update) }
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.refreshElapsed()
        }
    }

    func refreshElapsed() {
        elapsed = completedDuration + (activeStartedAt.map { max(0, now().timeIntervalSince($0)) } ?? 0)
        if let recordingID {
            let url = Self.recordingFileURL(for: recordingID)
            recordedBytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? recordedBytes
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    /// 录音文件位置：Application Support/FlashNote/audio/{id}.m4a
    static func recordingFileURL(for id: UUID) -> URL {
        AppEnvironment.defaultStoreDirectory()
            .appendingPathComponent("audio", isDirectory: true)
            .appendingPathComponent("\(id.uuidString).m4a")
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
