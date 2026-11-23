#if os(macOS)
import Foundation
import Testing
@testable import FlashNoteMac

struct USBVolumeTransferChannelTests {
    @Test func transferCopiesAudioWithoutChangingBytes() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("USBTransferTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let source = directory.appendingPathComponent("source.wav")
        let destination = directory.appendingPathComponent("audio/imported.wav")
        let audio = Data((0..<(1_048_576 + 73)).map { UInt8($0 % 251) })
        try audio.write(to: source)
        var lastProgress = 0.0

        let filename = try await USBVolumeTransferChannel().transfer(
            sourceURL: source, to: destination,
            onProgress: { progress, _ in lastProgress = progress }
        )

        #expect(filename == "imported.wav")
        #expect(try Data(contentsOf: destination) == audio)
        #expect(lastProgress == 1)
    }

    @Test func missingSourceDoesNotLeaveDestination() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("USBTransferTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("missing.wav")
        let destination = directory.appendingPathComponent("audio/imported.wav")

        do {
            _ = try await USBVolumeTransferChannel().transfer(
                sourceURL: source, to: destination, onProgress: { _, _ in }
            )
            Issue.record("Missing source must fail")
        } catch {
            #expect(!FileManager.default.fileExists(atPath: destination.path))
        }
    }
}
#endif
