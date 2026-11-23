import AVFoundation
import Combine

/// 音频播放器（AVPlayer 封装）。
@Observable
final class AudioPlayer {
    private let player = AVPlayer()
    private(set) var isPlaying = false
    private(set) var duration: TimeInterval = 0
    private(set) var currentTime: TimeInterval = 0
    private(set) var playbackRate: Float = 1
    private var timeObserver: Any?

    func load(url: URL, fallbackDuration: TimeInterval = 0) {
        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)
        isPlaying = false
        currentTime = 0
        duration = max(0, fallbackDuration)
        let seconds = item.asset.duration.seconds
        if seconds.isFinite && !seconds.isNaN {
            duration = seconds
        }
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] time in
            self?.currentTime = time.seconds
        }
    }

    func play() {
        player.playImmediately(atRate: playbackRate)
        isPlaying = true
    }

    func pause() {
        player.pause()
        isPlaying = false
    }

    func stop() {
        player.pause()
        player.seek(to: .zero)
        isPlaying = false
        currentTime = 0
    }

    func seek(to seconds: TimeInterval) {
        let target = Self.clampedSeekTime(seconds, duration: duration)
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600))
        currentTime = target
    }

    func skip(by seconds: TimeInterval) { seek(to: currentTime + seconds) }

    func cyclePlaybackRate() {
        let rates: [Float] = [1, 1.25, 1.5, 2]
        let current = rates.firstIndex(of: playbackRate) ?? 0
        playbackRate = rates[(current + 1) % rates.count]
        if isPlaying { player.rate = playbackRate }
    }

    static func clampedSeekTime(_ seconds: TimeInterval, duration: TimeInterval) -> TimeInterval {
        max(0, min(seconds, max(0, duration)))
    }

    deinit {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
        }
    }

    static func formatTime(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        if total >= 3600 {
            return String(format: "%02d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
        }
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
