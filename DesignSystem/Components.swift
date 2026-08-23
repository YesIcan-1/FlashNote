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

/// 轻量状态胶囊，用于连接、下载和处理状态。
struct StatusPill: View {
    enum Tone {
        case accent, success, warning, neutral, destructive

        var foreground: Color {
            switch self {
            case .accent: AppTheme.accent
            case .success: AppTheme.success
            case .warning: AppTheme.warning
            case .neutral: AppTheme.secondaryText
            case .destructive: AppTheme.destructive
            }
        }

        var background: Color {
            switch self {
            case .accent: AppTheme.infoBackground
            case .success: AppTheme.successBackground
            case .warning: AppTheme.warningBackground
            case .neutral: AppTheme.elevatedSurface
            case .destructive: AppTheme.destructive.opacity(0.14)
            }
        }

        var border: Color {
            switch self {
            case .neutral: AppTheme.border
            case .accent, .success, .warning, .destructive: Color.clear
            }
        }
    }

    let title: String
    var symbol: String?
    var tone: Tone = .neutral

    var body: some View {
        Label {
            Text(title)
        } icon: {
            if let symbol { Image(systemName: symbol) }
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(tone.foreground)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(tone.background, in: Capsule())
        .overlay {
            Capsule().stroke(tone.border, lineWidth: 1)
        }
    }
}

struct SectionHeading<Trailing: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder let trailing: Trailing

    init(_ title: String, subtitle: String? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.title3.weight(.bold))
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(AppTheme.secondaryText)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
    }
}

struct MetadataText: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.monospacedDigit())
            .foregroundStyle(AppTheme.secondaryText)
    }
}

/// 卡片容器。
struct Card<Content: View>: View {
    @ViewBuilder let content: Content
    var padding: CGFloat = 18

    var body: some View {
        content
            .padding(padding)
            .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous)
                    .stroke(AppTheme.border, lineWidth: 1)
            }
            .shadow(color: AppTheme.cardShadow, radius: 8, y: 2)
    }
}
