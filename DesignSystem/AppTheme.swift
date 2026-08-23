import SwiftUI

/// FlashNote 的语义化色板。所有页面只使用这些层级，当前应用采用固定浅色调。
enum AppTheme {
    // 保持现有品牌强调色；其余语义色只负责固定浅色调中的层级。
    static let accent = Color(red: 0.039, green: 0.518, blue: 1.0)
    static let accentMuted = Color(red: 0.039, green: 0.518, blue: 1.0).opacity(0.12)
    static let pageBackground = Color.white
    static let cardBackground = Color.white
    static let elevatedSurface = Color.white
    static let background = Color.white
    static let border = Color.black.opacity(0.075)
    static let primaryText = Color(red: 0.10, green: 0.11, blue: 0.13)
    static let secondaryText = Color(red: 0.38, green: 0.40, blue: 0.44)
    static let tertiaryText = Color(red: 0.53, green: 0.55, blue: 0.59)
    static let preferredColorScheme: ColorScheme = .light
    static let destructive = Color(red: 0.88, green: 0.20, blue: 0.23)
    static let warning = Color(red: 0.84, green: 0.49, blue: 0.08)
    static let success = Color(red: 0.10, green: 0.56, blue: 0.34)
    static let successBackground = Color(red: 0.10, green: 0.56, blue: 0.34).opacity(0.14)
    static let infoBackground = Color(red: 0.039, green: 0.518, blue: 1.0).opacity(0.14)
    static let warningBackground = Color(red: 0.84, green: 0.49, blue: 0.08).opacity(0.14)

    static let cardCornerRadius: CGFloat = 20
    static let compactCornerRadius: CGFloat = 13
    static let cardShadow = Color.black.opacity(0.022)
}
