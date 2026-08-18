import Foundation
import AVFoundation

/// AVAudioEngine 采集：输入 tap → 写 AVAudioFile（PCM .caf）+ 电平回调 + 缓冲泵出。
final class AudioService: AudioRecording {
    var onLevel: ((Float) -> Void)?
    var onBuffer: ((AVAudioPCMBuffer) -> Void)?
    private(set) var isRecording = false

    private let engine = AVAudioEngine()
    private var file: AVAudioFile?

    func startRecording(to url: URL) throws {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        file = try AVAudioFile(forWriting: url, settings: format.settings)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.handle(buffer)
        }
        engine.prepare()
        try engine.start()
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
        isRecording = false
    }

    private func handle(_ buffer: AVAudioPCMBuffer) {
        do { try file?.write(from: buffer) } catch { /* 写盘失败不阻断识别 */ }
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
