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
        #expect(RecordingStatusView.title(for: .recording) == "待转写")
        #expect(RecordingStatusView.title(for: .transcribed) == "已转写")
        #expect(RecordingStatusView.title(for: .summarized) == "已转写")
    }

    @Test func surfacesKeepTheirVisualHierarchy() {
        for surface in [AppTheme.pageBackground, AppTheme.cardBackground, AppTheme.elevatedSurface, AppTheme.background] {
            let components = resolvedComponents(for: surface)
            #expect(abs(components.alpha - 1.0) < 0.001)
        }
        let page = resolvedComponents(for: AppTheme.pageBackground)
        let elevated = resolvedComponents(for: AppTheme.elevatedSurface)
        let card = resolvedComponents(for: AppTheme.cardBackground)
        #if os(macOS)
        #expect(page.red < elevated.red)
        #expect(page.green < elevated.green)
        #expect(page.blue < elevated.blue)
        #expect(elevated.red < card.red)
        #expect(elevated.green < card.green)
        #expect(elevated.blue < card.blue)
        #else
        #expect(abs(page.red - 1.0) < 0.001)
        #expect(abs(elevated.red - 1.0) < 0.001)
        #expect(abs(card.red - 1.0) < 0.001)
        #endif
    }

    @Test func whiteSurfacesKeepDarkTextContrast() {
        let textColors: [(color: Color, minimumRatio: CGFloat)] = [
            (AppTheme.primaryText, 4.5),
            (AppTheme.secondaryText, 4.5),
            (AppTheme.tertiaryText, 3.0)
        ]
        for text in textColors {
            let components = resolvedComponents(for: text.color)
            #expect(components.alpha >= 0.99)
            #expect(contrastRatio(for: components) >= text.minimumRatio)
        }
    }

    @Test func whiteSurfacesKeepDarkTextComponents() {
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

    private func contrastRatio(for components: (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat)) -> CGFloat {
        let luminance = relativeLuminance(for: components)
        return (1.0 + 0.05) / (luminance + 0.05)
    }

    private func relativeLuminance(for components: (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat)) -> CGFloat {
        func linearize(_ value: CGFloat) -> CGFloat {
            value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linearize(components.red)
            + 0.7152 * linearize(components.green)
            + 0.0722 * linearize(components.blue)
    }
}
