import AVFoundation
import Foundation
import FlashNoteCore

/// 将设备的 40 字节 Opus 包解码为可播放 WAV，同时把 PCM 交给实时识别器。
final class DeviceRealtimeCapture {
    let recordingID: UUID
    let audioURL: URL
    private let decoder: OpusDecoder
    private let handle: FileHandle
    private let speech: LiveTranscriptionEngine?
    private let transcription: TranscriptionService?
    private var pending = Data()
    private var pendingPCM = Data()
    private var pendingSpeechSamples: [Float] = []
    private static let speechFrameCount = 3_200 // 16 kHz, 200 ms
    private(set) var packetCount = 0
    private(set) var pcmBytes = 0
    var duration: TimeInterval { Double(pcmBytes) / 32_000 }

    init(recordingID: UUID, storeDirectory: URL, speech: LiveTranscriptionEngine?,
         onPartial: @escaping (String?) -> Void,
         onSegment: @escaping (TranscriptSegment) -> Void,
         onRecognitionError: @escaping (Error) -> Void = { _ in }) throws {
        self.recordingID = recordingID
        decoder = try OpusDecoder()
        let directory = storeDirectory.appendingPathComponent("audio", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        audioURL = directory.appendingPathComponent("\(recordingID.uuidString).wav")
        FileManager.default.createFile(atPath: audioURL.path, contents: WAVEncoder.encode(samples: []))
        handle = try FileHandle(forWritingTo: audioURL)
        try handle.seekToEnd()
        pendingPCM.reserveCapacity(Self.speechFrameCount * MemoryLayout<Int16>.size)
        pendingSpeechSamples.reserveCapacity(Self.speechFrameCount)
        self.speech = speech
        if let speech {
            speech.onPartialText = { text in Task { @MainActor in onPartial(text) } }
            let service = TranscriptionService(recordingID: recordingID, engine: speech)
            service.onNewSegment = { segment in Task { @MainActor in onSegment(segment) } }
            service.onEngineError = { error in Task { @MainActor in onRecognitionError(error) } }
            do {
                try service.begin()
            } catch {
                try? handle.close()
                try? FileManager.default.removeItem(at: audioURL)
                throw error
            }
            transcription = service
        } else {
            transcription = nil
        }
    }

    func append(_ data: Data) throws {
        pending.append(data)
        while pending.count >= 40 {
            let packet = Data(pending.prefix(40))
            pending.removeFirst(40)
            let samples = try decoder.decode(packet: packet)
            samples.withUnsafeBufferPointer { buffer in
                pendingPCM.append(Data(buffer: buffer))
            }
            if pendingPCM.count >= Self.speechFrameCount * MemoryLayout<Int16>.size {
                try flushPCM()
            }
            packetCount += 1
            pcmBytes += samples.count * MemoryLayout<Int16>.size
            if speech != nil {
                for index in samples.indices {
                    pendingSpeechSamples.append(Float(samples[index]) / 32_768)
                }
                if pendingSpeechSamples.count >= Self.speechFrameCount {
                    flushSpeech()
                }
            }
        }
    }

    private func flushPCM() throws {
        guard !pendingPCM.isEmpty else { return }
        try handle.write(contentsOf: pendingPCM)
        pendingPCM.removeAll(keepingCapacity: true)
    }

    private func flushSpeech() {
        guard let speech, !pendingSpeechSamples.isEmpty,
              let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1),
              let audioBuffer = AVAudioPCMBuffer(pcmFormat: format,
                  frameCapacity: AVAudioFrameCount(pendingSpeechSamples.count)),
              let destination = audioBuffer.floatChannelData?.pointee else { return }
        audioBuffer.frameLength = AVAudioFrameCount(pendingSpeechSamples.count)
        for index in pendingSpeechSamples.indices {
            destination[index] = pendingSpeechSamples[index]
        }
        speech.append(audioBuffer)
        pendingSpeechSamples.removeAll(keepingCapacity: true)
    }

    func finish() throws -> Transcript? {
        try flushPCM()
        flushSpeech()
        speech?.finalizePending()
        speech?.cancel()
        let length = UInt32(clamping: pcmBytes)
        var riffSize = (36 &+ length).littleEndian
        var dataSize = length.littleEndian
        try handle.seek(toOffset: 4)
        try handle.write(contentsOf: Data(bytes: &riffSize, count: 4))
        try handle.seek(toOffset: 40)
        try handle.write(contentsOf: Data(bytes: &dataSize, count: 4))
        try handle.close()
        if packetCount == 0 {
            try? FileManager.default.removeItem(at: audioURL)
            return nil
        }
        return transcription?.finish()
    }
}
