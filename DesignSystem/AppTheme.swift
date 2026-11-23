import SwiftUI

/// FlashNote 的语义化色板。所有页面只使用这些层级，当前应用采用固定浅色调。
enum AppTheme {
    // 常规连接、完成、等待等状态统一使用品牌蓝；删除与错误仍用红色提醒。
    static let accent = Color(red: 0.039, green: 0.518, blue: 1.0)
    static let accentMuted = Color(red: 0.039, green: 0.518, blue: 1.0).opacity(0.12)
    #if os(macOS)
    static let pageBackground = Color(red: 0.955, green: 0.958, blue: 0.964)
    static let elevatedSurface = Color(red: 0.973, green: 0.975, blue: 0.978)
    #else
    static let pageBackground = Color.white
    static let elevatedSurface = Color.white
    #endif
    static let cardBackground = Color.white
    static let background = Color.white
    static let border = Color.black.opacity(0.09)
    static let primaryText = Color(red: 0.10, green: 0.11, blue: 0.13)
    static let secondaryText = Color(red: 0.38, green: 0.40, blue: 0.44)
    static let tertiaryText = Color(red: 0.53, green: 0.55, blue: 0.59)
    static let preferredColorScheme: ColorScheme = .light
    static let destructive = Color(red: 0.88, green: 0.20, blue: 0.23)
    static let warning = accent
    static let success = accent
    static let successBackground = accentMuted
    static let infoBackground = Color(red: 0.039, green: 0.518, blue: 1.0).opacity(0.14)
    static let warningBackground = accentMuted

    static let cardCornerRadius: CGFloat = 20
    static let compactCornerRadius: CGFloat = 13
    static let cardShadow = Color.black.opacity(0.022)
}
