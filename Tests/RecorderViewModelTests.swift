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

    func start() throws {
        guard !started else { throw TranscriptionError.invalidState("already started") }
        started = true
    }
    func append(_ buffer: AVAudioPCMBuffer) { appendedBuffers.append(buffer) }
    func cancel() { cancelled = true; started = false }

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
        #expect(vm.recordingTitle == "未命名录音")
    }

    @Test func startFailureSetsError() {
        let audio = MockAudio(); audio.failToStart = true
        let (vm, _, _, _) = makeVM(audio: audio)
        #expect(throws: TranscriptionError.self) { try vm.start() }
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

    @Test func elapsedFormatting() {
        #expect(RecorderViewModel.formatElapsed(0) == "00:00:00")
        #expect(RecorderViewModel.formatElapsed(3725) == "01:02:05")
        #expect(RecorderViewModel.formatElapsed(59) == "00:00:59")
    }
}
