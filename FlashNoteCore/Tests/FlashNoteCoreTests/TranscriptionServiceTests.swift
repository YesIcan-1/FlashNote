import Foundation
import Testing
@testable import FlashNoteCore

/// 测试替身：start 时同步发出两个段落。
final class MockTranscriptionEngine: TranscriptionEngine {
    let displayName = "MockEngine"
    let isRealtime = true
    var onSegment: ((TranscriptSegment) -> Void)?
    var onError: ((Error) -> Void)?
    private(set) var started = false
    private(set) var cancelled = false

    func start() throws {
        started = true
        onSegment?(TranscriptSegment(startTime: 0, text: "你好。"))
        onSegment?(TranscriptSegment(startTime: 2, text: "这是一段测试转写。"))
    }

    func cancel() {
        cancelled = true
    }
}

struct TranscriptionServiceTests {
    @Test func beginAppendsSegments() throws {
        let engine = MockTranscriptionEngine()
        let service = TranscriptionService(recordingID: UUID(), engine: engine)
        try service.begin()
        #expect(engine.started)
        #expect(service.transcript.segments.count == 2)
        #expect(service.transcript.fullText == "你好。\n这是一段测试转写。")
    }

    @Test func finishReturnsTranscript() throws {
        let service = TranscriptionService(recordingID: UUID(), engine: MockTranscriptionEngine())
        try service.begin()
        let transcript = service.finish()
        #expect(transcript.segments.count == 2)
    }

    @Test func cancelStopsEngine() throws {
        let engine = MockTranscriptionEngine()
        let service = TranscriptionService(recordingID: UUID(), engine: engine)
        try service.begin()
        service.cancel()
        #expect(engine.cancelled)
    }

    @Test func engineErrorIsCaptured() throws {
        final class FailingEngine: TranscriptionEngine {
            let displayName = "Failing"
            let isRealtime = false
            var onSegment: ((TranscriptSegment) -> Void)?
            var onError: ((Error) -> Void)?
            func start() throws {
                onError?(TranscriptionError.engineFailed("boom"))
            }
            func cancel() {}
        }
        let service = TranscriptionService(recordingID: UUID(), engine: FailingEngine())
        try service.begin()
        #expect(service.lastError as? TranscriptionError == .engineFailed("boom"))
    }

    @Test func nonFinalSegmentsAreDropped() throws {
        final class PartialEngine: TranscriptionEngine {
            let displayName = "Partial"
            let isRealtime = true
            var onSegment: ((TranscriptSegment) -> Void)?
            var onError: ((Error) -> Void)?
            func start() throws {
                onSegment?(TranscriptSegment(startTime: 0, text: "临时", isFinal: false))
                onSegment?(TranscriptSegment(startTime: 0, text: "你好。", isFinal: true))
                onSegment?(TranscriptSegment(startTime: 2, text: "还在想…", isFinal: false))
            }
            func cancel() {}
        }
        let service = TranscriptionService(recordingID: UUID(), engine: PartialEngine())
        try service.begin()
        #expect(service.transcript.segments.count == 1)
        #expect(service.transcript.fullText == "你好。")
    }
}
