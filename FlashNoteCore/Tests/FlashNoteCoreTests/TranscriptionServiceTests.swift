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

    @Test func asyncSegmentAfterBegin() async throws {
        final class AsyncEngine: TranscriptionEngine {
            let displayName = "Async"
            let isRealtime = true
            var onSegment: ((TranscriptSegment) -> Void)?
            var onError: ((Error) -> Void)?
            func start() throws {
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) { [weak self] in
                    self?.onSegment?(TranscriptSegment(startTime: 0, text: "异步段落。"))
                }
            }
            func cancel() {}
        }
        let service = TranscriptionService(recordingID: UUID(), engine: AsyncEngine())
        try service.begin()
        try await Task.sleep(nanoseconds: 300_000_000)
        #expect(service.transcript.segments.count == 1)
        #expect(service.transcript.fullText == "异步段落。")
    }

    @Test func concurrentAppendsStress() throws {
        final class BurstEngine: TranscriptionEngine {
            let displayName = "Burst"
            let isRealtime = true
            var onSegment: ((TranscriptSegment) -> Void)?
            var onError: ((Error) -> Void)?
            func start() throws {
                let total = 200
                DispatchQueue.concurrentPerform(iterations: total) { i in
                    self.onSegment?(TranscriptSegment(startTime: TimeInterval(i), text: "段\(i)"))
                }
            }
            func cancel() {}
        }
        let service = TranscriptionService(recordingID: UUID(), engine: BurstEngine())
        try service.begin()
        // concurrentPerform 同步阻塞至全部完成；NSLock 保护下不应丢失任何段落
        #expect(service.transcript.segments.count == 200)
    }

    @Test func beginThrowIsRecorded() {
        final class ThrowingEngine: TranscriptionEngine {
            let displayName = "Throwing"
            let isRealtime = false
            var onSegment: ((TranscriptSegment) -> Void)?
            var onError: ((Error) -> Void)?
            func start() throws { throw TranscriptionError.engineUnavailable }
            func cancel() {}
        }
        let service = TranscriptionService(recordingID: UUID(), engine: ThrowingEngine())
        #expect(throws: TranscriptionError.self) { try service.begin() }
        #expect(service.lastError as? TranscriptionError == .engineUnavailable)
    }
}
