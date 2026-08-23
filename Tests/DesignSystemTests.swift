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
        let components = resolvedComponents(for: AppTheme.accent)
        #expect(abs(components.red - 0.039) < 0.01)
        #expect(abs(components.green - 0.518) < 0.01)
        #expect(abs(components.blue - 1.0) < 0.01)
    }

    @Test func statusBadgeStyling() {
        #expect(RecordingStatusView.title(for: .recording) == "录音中")
        #expect(RecordingStatusView.title(for: .transcribed) == "已转写")
        #expect(RecordingStatusView.title(for: .summarized) == "已出纪要")
    }

    @Test func sharedSurfacesResolveToWhite() {
        for surface in [AppTheme.pageBackground, AppTheme.cardBackground, AppTheme.elevatedSurface] {
            let components = resolvedComponents(for: surface)
            #expect(abs(components.red - 1.0) < 0.001)
            #expect(abs(components.green - 1.0) < 0.001)
            #expect(abs(components.blue - 1.0) < 0.001)
            #expect(abs(components.alpha - 1.0) < 0.001)
        }
    }

    @Test func whiteSurfacesKeepDarkTextContrast() {
        for textColor in [AppTheme.primaryText, AppTheme.secondaryText, AppTheme.tertiaryText] {
            let components = resolvedComponents(for: textColor)
            #expect(components.red < 0.60)
            #expect(components.green < 0.60)
            #expect(components.blue < 0.60)
        }
    }

    @Test func appUsesFixedLightAppearance() {
        #expect(AppTheme.preferredColorScheme == .light)
    }

    private func resolvedComponents(for color: Color) -> (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
#if os(macOS)
        NSColor(color).usingColorSpace(.sRGB)!.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
#else
        UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
#endif
        return (red, green, blue, alpha)
    }
}
