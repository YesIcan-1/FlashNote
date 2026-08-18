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
}
