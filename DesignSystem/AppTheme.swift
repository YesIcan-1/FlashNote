import SwiftUI

/// 设计语言：专业蓝（与 Assets 的 AccentColor 一致）。
enum AppTheme {
    static let accent = Color(red: 0.039, green: 0.518, blue: 1.0)          // #0A84FF
    static let background = Color.primary.opacity(0.06)
    static var cardBackground: Color {
#if os(macOS)
        Color(nsColor: .windowBackgroundColor)
#else
        Color(uiColor: .systemBackground)
#endif
    }
    static let primaryText = Color.primary
    static let secondaryText = Color.secondary
    static let destructive = Color(red: 1.0, green: 0.231, blue: 0.188)     // #FF3B30
    static let success = Color(red: 0.102, green: 0.62, blue: 0.361)        // #1A9E5C
    static let successBackground = Color(red: 0.91, green: 0.969, blue: 0.933)
    static let infoBackground = Color(red: 0.91, green: 0.945, blue: 1.0)
}
