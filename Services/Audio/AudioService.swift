import Foundation
import os
import AVFoundation
import FlashNoteCore

/// AVAudioEngine 采集：输入 tap → AAC 文件 + 电平回调 + 实时识别缓冲。
final class AudioService: AudioRecording {
    static let logger = Logger(subsystem: "com.flashnote.mac", category: "audio")

    var onLevel: ((Float) -> Void)?
    var onBuffer: ((AVAudioPCMBuffer) -> Void)?
    private(set) var isRecording = false

    private let engine = AVAudioEngine()
    private var file: AVAudioFile?
    private var writerConverter: AVAudioConverter?

    func startRecording(to url: URL) throws {
        // 确保音频目录存在
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

        let input = engine.inputNode
        var format = input.outputFormat(forBus: 0)
        if format.channelCount == 0 || format.sampleRate == 0 {
            format = input.inputFormat(forBus: 0)
        }
        guard format.channelCount > 0, format.sampleRate > 0 else {
            throw TranscriptionError.engineUnavailable
        }
        AudioService.logger.info("input format: channels=\(format.channelCount) rate=\(format.sampleRate)")

        do {
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 64_000
            ]
            file = try AVAudioFile(forWriting: url, settings: settings,
                                   commonFormat: .pcmFormatFloat32, interleaved: false)
            guard let outputFormat = file?.processingFormat else {
                file = nil
                throw TranscriptionError.engineFailed("无法转换麦克风音频格式")
            }
            let samePCMFormat = format.sampleRate == outputFormat.sampleRate
                && format.channelCount == outputFormat.channelCount
                && format.commonFormat == outputFormat.commonFormat
                && format.isInterleaved == outputFormat.isInterleaved
            if samePCMFormat {
                writerConverter = nil
            } else {
                guard let converter = AVAudioConverter(from: format, to: outputFormat) else {
                    file = nil
                    throw TranscriptionError.engineFailed("无法转换麦克风音频格式")
                }
                writerConverter = converter
            }
        } catch {
            AudioService.logger.error("AVAudioFile failed: \(String(describing: error), privacy: .public)")
            throw error
        }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.handle(buffer)
        }
        do {
            try engine.start()
        } catch {
            AudioService.logger.error("engine.start failed: \(String(describing: error), privacy: .public)")
            input.removeTap(onBus: 0)
            file = nil
            writerConverter = nil
            throw error
        }
        isRecording = true
    }

    func pause() {
        guard isRecording else { return }
        engine.pause()
    }

    func resume() {
        guard isRecording else { return }
        try? engine.start()
    }

    func stop() {
        guard isRecording else { return }
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        file = nil
        writerConverter = nil
        isRecording = false
    }

    private func handle(_ buffer: AVAudioPCMBuffer) {
        if let file, let converter = writerConverter {
            let ratio = file.processingFormat.sampleRate / buffer.format.sampleRate
            let capacity = AVAudioFrameCount(ceil(Double(buffer.frameLength) * ratio) + 64)
            if let converted = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: capacity) {
                var providedInput = false
                var conversionError: NSError?
                let status = converter.convert(to: converted, error: &conversionError) { _, inputStatus in
                    if providedInput {
                        inputStatus.pointee = .noDataNow
                        return nil
                    }
                    providedInput = true
                    inputStatus.pointee = .haveData
                    return buffer
                }
                if status != .error, converted.frameLength > 0 {
                    do { try file.write(from: converted) }
                    catch { AudioService.logger.error("audio write failed: \(String(describing: error), privacy: .public)") }
                } else if let conversionError {
                    AudioService.logger.error("audio conversion failed: \(conversionError.localizedDescription, privacy: .public)")
                }
            }
        } else if let file {
            do { try file.write(from: buffer) }
            catch { AudioService.logger.error("audio write failed: \(String(describing: error), privacy: .public)") }
        }
        onLevel?(Self.rms(buffer))
        onBuffer?(buffer)
    }

    /// 缓冲 → 归一化 RMS（0...1）。
    static func rms(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let channel = buffer.floatChannelData?[0] else { return 0 }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return 0 }
        let samples = Array(UnsafeBufferPointer(start: channel, count: frames))
        return rms(samples)
    }

    /// 采样数组 → 归一化 RMS（0...1）。纯函数（可测）。
    static func rms(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        let sum = samples.reduce(Float(0)) { $0 + $1 * $1 }
        return min(1, sqrt(sum / Float(samples.count)))
    }
}
