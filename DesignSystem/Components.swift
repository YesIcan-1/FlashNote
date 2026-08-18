import SwiftUI
import FlashNoteCore

/// 状态徽章（录音中/已转写/已出纪要）。
struct RecordingStatusView: View {
    let status: RecordingStatus

    var body: some View {
        Text(Self.title(for: status))
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(background, in: Capsule())
            .foregroundStyle(foreground)
    }

    static func title(for status: RecordingStatus) -> String {
        switch status {
        case .recording: "录音中"
        case .transcribed: "已转写"
        case .summarized: "已出纪要"
        }
    }

    private var background: Color {
        switch status {
        case .recording: AppTheme.infoBackground
        case .transcribed: AppTheme.successBackground
        case .summarized: AppTheme.infoBackground
        }
    }

    private var foreground: Color {
        switch status {
        case .recording: AppTheme.accent
        case .transcribed: AppTheme.success
        case .summarized: AppTheme.accent
        }
    }
}

/// 卡片容器。
struct Card<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(14)
            .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: .black.opacity(0.05), radius: 4, y: 1)
    }
}
