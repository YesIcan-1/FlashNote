import Testing
import Foundation
import AVFoundation
import FlashNoteCore
#if os(macOS)
@testable import FlashNoteMac
#else
@testable import FlashNote
#endif

/// 测试替身：立即进入录音状态，可编程推送局部/定稿文本。
final class MockLiveEngine: LiveTranscriptionEngine {
    let displayName = "Mock"
    let isRealtime = true
    var onSegment: ((TranscriptSegment) -> Void)?
    var onError: ((Error) -> Void)?
    var onPartialText: ((String?) -> Void)?
    private(set) var started = false
    private(set) var cancelled = false
    private(set) var appendedBuffers: [AVAudioPCMBuffer] = []
    var failToStart = false
    var pendingText: String?

    func start() throws {
        if failToStart { throw TranscriptionError.engineUnavailable }
        guard !started else { throw TranscriptionError.invalidState("already started") }
        started = true
    }
    func append(_ buffer: AVAudioPCMBuffer) { appendedBuffers.append(buffer) }
    func cancel() { cancelled = true; started = false }
    func finalizePending() {
        if let pendingText { emitFinal(pendingText); self.pendingText = nil }
    }

    func emitPartial(_ text: String?) { onPartialText?(text) }
    func emitFinal(_ text: String) { onSegment?(TranscriptSegment(startTime: 0, text: text, isFinal: true)) }
}

/// 测试替身：记录生命周期，不碰真实硬件。
final class MockAudio: AudioRecording {
    var onLevel: ((Float) -> Void)?
    var onBuffer: ((AVAudioPCMBuffer) -> Void)?
    private(set) var isRecording = false
    private(set) var startedURL: URL?
    private(set) var stopped = false
    private(set) var pausedCount = 0
    private(set) var resumedCount = 0
    var failToStart = false

    func startRecording(to url: URL) throws {
        if failToStart { throw TranscriptionError.engineFailed("mic unavailable") }
        startedURL = url
        isRecording = true
    }
    func pause() { pausedCount += 1 }
    func resume() { resumedCount += 1 }
    func stop() { stopped = true; isRecording = false }
}

struct RecorderViewModelTests {
    private func makeVM(
        audio: MockAudio = MockAudio(),
        engine: MockLiveEngine = MockLiveEngine(),
        store: InMemoryStore = InMemoryStore()
    ) -> (RecorderViewModel, MockAudio, MockLiveEngine, InMemoryStore) {
        let vm = RecorderViewModel(audio: audio, engine: engine, store: store)
        return (vm, audio, engine, store)
    }

    @Test func startEntersRecordingAndWiresCallbacks() throws {
        let (vm, audio, engine, _) = makeVM()
        try vm.start()
        #expect(vm.phase == .recording)
        #expect(audio.isRecording)
        #expect(engine.started)
        #expect(vm.recordingID != nil)
        #expect(vm.recordingTitle.range(of: #"^note\d{8}-\d{6}$"#, options: .regularExpression) != nil)
    }

    @Test func startFailureSetsError() {
        let audio = MockAudio(); audio.failToStart = true
        let (vm, _, _, _) = makeVM(audio: audio)
        #expect(throws: TranscriptionError.self) { try vm.start() }
        #expect(vm.phase == .idle)
    }

    @Test func speechStartFailureStopsMicrophone() {
        let engine = MockLiveEngine(); engine.failToStart = true
        let (vm, audio, _, _) = makeVM(engine: engine)
        #expect(throws: TranscriptionError.self) { try vm.start() }
        #expect(audio.stopped)
        #expect(!audio.isRecording)
        #expect(vm.phase == .idle)
    }

    @Test func partialAndFinalSegmentsUpdateUI() throws {
        let (vm, _, engine, _) = makeVM()
        try vm.start()
        engine.emitPartial("你好")
        #expect(vm.partialText == "你好")
        engine.emitPartial("你好世界")
        #expect(vm.partialText == "你好世界")
        engine.emitFinal("你好世界。")
        #expect(vm.partialText == nil)
        #expect(vm.segments.count == 1)
    }

    @Test func engineErrorAppearsWhileRecording() throws {
        let (vm, _, engine, _) = makeVM()
        try vm.start()
        engine.onError?(TranscriptionError.engineFailed("speech failed"))
        #expect(vm.errorMessage?.contains("转写引擎出错") == true)
    }

    @Test func stopSavesRecordingAndTranscript() throws {
        let (vm, audio, engine, store) = makeVM()
        try vm.start()
        engine.emitFinal("这是一段转写。")
        vm.stop()
        #expect(vm.phase == .idle)
        #expect(audio.stopped)
        #expect(engine.cancelled)
        let recID = try #require(vm.recordingID)
        let savedRec = try store.fetchRecording(id: recID)
        #expect(savedRec?.status == .transcribed)
        let savedTranscript = try store.fetchTranscript(recordingID: recID)
        #expect(savedTranscript?.fullText == "这是一段转写。")
    }

    @Test func stopKeepsRecognizedTextThatHasNotBecomeFinal() throws {
        let (vm, _, engine, store) = makeVM()
        try vm.start()
        engine.pendingText = "停止前已识别的文字"
        engine.emitPartial(engine.pendingText)
        vm.stop()
        let recID = try #require(vm.recordingID)
        #expect(try store.fetchTranscript(recordingID: recID)?.fullText == "停止前已识别的文字")
        #expect(try store.fetchRecording(id: recID)?.status == .transcribed)
    }

    @Test func stopKeepsVisibleTextWhenRecognizerHasNoSegments() throws {
        let (vm, _, engine, store) = makeVM()
        try vm.start()
        engine.emitPartial("屏幕上已识别的文字")
        vm.stop()
        let recID = try #require(vm.recordingID)
        #expect(try store.fetchTranscript(recordingID: recID)?.fullText == "屏幕上已识别的文字")
        #expect(try store.fetchRecording(id: recID)?.status == .transcribed)
    }

    @Test func stopKeepsSentenceBreaksWhenOnlyPartialTextExists() throws {
        let (vm, _, engine, store) = makeVM()
        try vm.start()
        engine.emitPartial("第一句。第二句。")
        vm.stop()
        let recID = try #require(vm.recordingID)
        #expect(try store.fetchTranscript(recordingID: recID)?.fullText == "第一句。\n第二句。")
    }

    @Test func emptyRecognitionRemainsPendingTranscription() throws {
        let (vm, _, _, store) = makeVM()
        try vm.start()
        vm.stop()
        let recID = try #require(vm.recordingID)
        #expect(try store.fetchRecording(id: recID)?.status == .recording)
    }

    @Test func pauseResumeTransitions() throws {
        let (vm, audio, _, _) = makeVM()
        try vm.start()
        vm.pause()
        #expect(vm.phase == .paused)
        #expect(audio.pausedCount == 1)
        vm.resume()
        #expect(vm.phase == .recording)
        #expect(audio.resumedCount == 1)
    }

    @Test func pausedTimeIsNotCountedInRecordingDuration() throws {
        var current = Date(timeIntervalSince1970: 1_000)
        let audio = MockAudio(), engine = MockLiveEngine(), store = InMemoryStore()
        let vm = RecorderViewModel(audio: audio, engine: engine, store: store, now: { current })
        try vm.start()
        current.addTimeInterval(10)
        vm.pause()
        #expect(vm.elapsed == 10)
        current.addTimeInterval(15)
        vm.refreshElapsed()
        #expect(vm.elapsed == 10)
        vm.resume()
        current.addTimeInterval(5)
        vm.stop()
        #expect(vm.elapsed == 15)
        let recID = try #require(vm.recordingID)
        #expect(try store.fetchRecording(id: recID)?.duration == 15)
    }

    @Test func elapsedFormatting() {
        #expect(RecorderViewModel.formatElapsed(0) == "00:00:00")
        #expect(RecorderViewModel.formatElapsed(3725) == "01:02:05")
        #expect(RecorderViewModel.formatElapsed(59) == "00:00:59")
    }

    @Test func errorTextMapping() {
        #expect(RecorderViewModel.errorText(for: TranscriptionError.permissionDenied).contains("权限"))
        #expect(RecorderViewModel.errorText(for: TranscriptionError.engineUnavailable).contains("不可用"))
        #expect(RecorderViewModel.errorText(for: TranscriptionError.engineFailed("boom")).contains("boom"))
    }
}

struct LiveTranscriptSegmenterTests {
    @Test func splitsChineseAndEnglishSentencesForLivePreview() {
        #expect(LiveTranscriptSegmenter.lines("今天讨论排期。明天确认资源！然后开始实施。") == [
            "今天讨论排期。", "明天确认资源！", "然后开始实施。"
        ])
        #expect(LiveTranscriptSegmenter.lines("First point. Second point? Done!") == [
            "First point.", "Second point?", "Done!"
        ])
    }

    @Test func doesNotForceShortLinesWhenPreviewCanUseFullWidth() {
        let lines = LiveTranscriptSegmenter.lines(String(repeating: "这是持续识别的内容", count: 9))
        #expect(lines.count == 1)
        #expect(LiveTranscriptSegmenter.lines("测试测试现在可以分段了吗？再次测试我需要分段") == [
            "测试测试现在可以分段了吗？", "再次测试我需要分段"
        ])
    }

    @Test func groupsRecognitionTokensBySentenceAndPause() {
        let tokens = [
            LiveSpeechToken(startTime: 0, endTime: 0.4, text: "今天"),
            LiveSpeechToken(startTime: 0.4, endTime: 0.9, text: "讨论排期。"),
            LiveSpeechToken(startTime: 1.0, endTime: 1.4, text: "明天"),
            LiveSpeechToken(startTime: 2.9, endTime: 3.4, text: "确认资源"),
        ]
        let segments = LiveTranscriptSegmenter.segments(tokens)
        #expect(segments.map(\.text) == ["今天讨论排期。", "明天", "确认资源"])
        #expect(segments.map(\.startTime) == [0, 1.0, 2.9])
    }

    @Test func shortPauseStartsANewLine() {
        let tokens = [
            LiveSpeechToken(startTime: 0, endTime: 0.4, text: "第一句"),
            LiveSpeechToken(startTime: 0.9, endTime: 1.3, text: "第二句"),
        ]
        #expect(LiveTranscriptSegmenter.segments(tokens).map(\.text) == ["第一句", "第二句"])
    }
}
