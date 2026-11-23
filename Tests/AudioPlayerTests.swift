import Testing
import Foundation
#if os(macOS)
@testable import FlashNoteMac
#else
@testable import FlashNote
#endif

struct AudioPlayerTests {
    @Test func formatTime() {
        #expect(AudioPlayer.formatTime(0) == "00:00")
        #expect(AudioPlayer.formatTime(65) == "01:05")
        #expect(AudioPlayer.formatTime(3725) == "01:02:05")
    }

    @Test func seekingStaysWithinAudioBounds() {
        #expect(AudioPlayer.clampedSeekTime(-10, duration: 173) == 0)
        #expect(AudioPlayer.clampedSeekTime(50, duration: 173) == 50)
        #expect(AudioPlayer.clampedSeekTime(180, duration: 173) == 173)
    }
}
