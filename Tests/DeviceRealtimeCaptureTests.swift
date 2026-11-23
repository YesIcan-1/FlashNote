import Foundation
import Testing
#if os(macOS)
@testable import FlashNoteMac
#else
@testable import FlashNote
#endif

struct DeviceRealtimeCaptureTests {
    @Test func emptySessionDoesNotLeaveAnAudioFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let capture = try DeviceRealtimeCapture(recordingID: UUID(), storeDirectory: directory,
            speech: nil, onPartial: { _ in }, onSegment: { _ in })
        #expect(try capture.finish() == nil)
        #expect(!FileManager.default.fileExists(atPath: capture.audioURL.path))
    }

    @Test func realtimePacketsBecomePlayableWAV() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let capture = try DeviceRealtimeCapture(recordingID: UUID(), storeDirectory: directory,
            speech: nil, onPartial: { _ in }, onSegment: { _ in })
        let packet = Data([0xF8, 0xFF, 0xFE] + Array(repeating: UInt8(0), count: 37))
        try capture.append(packet.prefix(17))
        #expect(capture.packetCount == 0)
        try capture.append(packet.dropFirst(17))
        #expect(capture.packetCount == 1)
        _ = try capture.finish()
        let wav = try Data(contentsOf: capture.audioURL)
        #expect(wav.starts(with: Data("RIFF".utf8)))
        #expect(wav.count > 44)
    }

    @Test func speechReceivesTwoHundredMillisecondBatchesAndFlushesTail() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let engine = MockLiveEngine()
        let capture = try DeviceRealtimeCapture(recordingID: UUID(), storeDirectory: directory,
            speech: engine, onPartial: { _ in }, onSegment: { _ in })
        let packet = Data([0xF8, 0xFF, 0xFE] + Array(repeating: UInt8(0), count: 37))
        for _ in 0..<10 { try capture.append(packet) }
        #expect(engine.appendedBuffers.count == 1)
        #expect(engine.appendedBuffers[0].frameLength == 3_200)
        try capture.append(packet)
        _ = try capture.finish()
        #expect(engine.appendedBuffers.count == 2)
        #expect(engine.appendedBuffers[1].frameLength == 320)
        let wav = try Data(contentsOf: capture.audioURL)
        #expect(wav.count == 44 + 11 * 320 * 2)
    }
}
