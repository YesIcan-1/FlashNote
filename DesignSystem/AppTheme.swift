import SwiftUI

/// FlashNote 的语义化色板。所有页面只使用这些层级，系统浅/深色会自动适配。
enum AppTheme {
    // 保持现有品牌强调色；其余语义色只负责层级与主题适配。
    static let accent = Color(red: 0.039, green: 0.518, blue: 1.0)
    static let accentMuted = Color(red: 0.039, green: 0.518, blue: 1.0).opacity(0.12)
    static let background = Color.primary.opacity(0.055)
    static var pageBackground: Color {
#if os(macOS)
        Color(nsColor: .underPageBackgroundColor)
#else
        Color(uiColor: .systemGroupedBackground)
#endif
    }
    static var cardBackground: Color {
#if os(macOS)
        Color(nsColor: .windowBackgroundColor)
#else
        Color(uiColor: .systemBackground)
#endif
    }
    static var elevatedSurface: Color {
#if os(macOS)
        Color(nsColor: .controlBackgroundColor)
#else
        Color(uiColor: .secondarySystemBackground)
#endif
    }
    static let border = Color.primary.opacity(0.10)
    static let primaryText = Color.primary
    static let secondaryText = Color.secondary
    static let tertiaryText = Color.secondary.opacity(0.72)
    static let destructive = Color(red: 0.88, green: 0.20, blue: 0.23)
    static let warning = Color(red: 0.84, green: 0.49, blue: 0.08)
    static let success = Color(red: 0.10, green: 0.56, blue: 0.34)
    static let successBackground = Color(red: 0.10, green: 0.56, blue: 0.34).opacity(0.14)
    static let infoBackground = Color(red: 0.039, green: 0.518, blue: 1.0).opacity(0.14)
    static let warningBackground = Color(red: 0.84, green: 0.49, blue: 0.08).opacity(0.14)

    static let cardCornerRadius: CGFloat = 20
    static let compactCornerRadius: CGFloat = 13
    static let cardShadow = Color.black.opacity(0.055)
}
