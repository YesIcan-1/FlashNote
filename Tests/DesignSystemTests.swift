import Testing
import SwiftUI
import FlashNoteCore
#if os(macOS)
@testable import FlashNoteMac
#else
@testable import FlashNote
#endif

struct DesignSystemTests {
    @Test func accentColorMatchesProfessionalBlue() {
        let color = AppTheme.accent
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
#if os(macOS)
        let resolved = NSColor(color).usingColorSpace(.sRGB)!
#else
        let resolved = color
#endif
        resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        #expect(abs(red - 0.039) < 0.01)
        #expect(abs(green - 0.518) < 0.01)
        #expect(abs(blue - 1.0) < 0.01)
    }

    @Test func statusBadgeStyling() {
        #expect(RecordingStatusView.title(for: .recording) == "录音中")
        #expect(RecordingStatusView.title(for: .transcribed) == "已转写")
        #expect(RecordingStatusView.title(for: .summarized) == "已出纪要")
    }
}
