import Foundation
import AVFoundation

/// 录音采集抽象（测试替身可注入 RecorderViewModel）。
protocol AudioRecording: AnyObject {
    /// 电平 0...1（RMS）。
    var onLevel: ((Float) -> Void)? { get set }
    /// 原始 PCM 缓冲（供识别引擎消费）。
    var onBuffer: ((AVAudioPCMBuffer) -> Void)? { get set }
    var isRecording: Bool { get }
    func startRecording(to url: URL) throws
    func pause()
    func resume()
    func stop()
}
