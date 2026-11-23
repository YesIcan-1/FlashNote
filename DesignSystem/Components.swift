import SwiftUI
import FlashNoteCore

/// 状态徽章（待转写/已转写/已出纪要）。
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
        case .recording: "待转写"
        case .transcribed: "已转写"
        case .summarized: "已转写"
        }
    }

    private var background: Color {
        switch status {
        case .recording: AppTheme.infoBackground
        case .transcribed: AppTheme.infoBackground
        case .summarized: AppTheme.infoBackground
        }
    }

    private var foreground: Color {
        switch status {
        case .recording: AppTheme.accent
        case .transcribed: AppTheme.accent
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

struct TaskProgressRing: View {
    let fraction: Double
    let label: String

    var body: some View {
        ZStack {
            Circle().stroke(AppTheme.border, lineWidth: 3)
            Circle()
                .trim(from: 0, to: min(1, max(0, fraction)))
                .stroke(AppTheme.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if fraction <= 0 { ProgressView().controlSize(.mini) }
            else { Text("\(Int(min(1, fraction) * 100))").font(.system(size: 9, weight: .semibold).monospacedDigit()) }
        }
        .frame(width: 34, height: 34)
        .accessibilityLabel(label)
        .accessibilityValue("\(Int(min(1, max(0, fraction)) * 100))%")
        .help(label)
    }
}

/// 文件卡片的状态直接围绕音频图标显示，完成后保留完整的蓝色细边框。
struct RecordingProgressIcon: View {
    let recording: Recording
    let progress: ProcessingProgress?
    var size: CGFloat = 48
    var symbol = "waveform"

    private var ringFraction: Double? {
        if let progress {
            if progress.stage == .completed { return 1 }
            if progress.stage == .failed { return min(progress.fraction, 0.9) }
            return progress.fraction
        }
        return recording.status == .recording ? nil : 1
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.23, style: .continuous)
                .fill(AppTheme.accentMuted)
                .frame(width: size - 8, height: size - 8)
            Image(systemName: symbol)
                .font(.system(size: size * 0.38, weight: .medium))
                .foregroundStyle(AppTheme.accent)
            if let ringFraction {
                RoundedRectangle(cornerRadius: size * 0.23, style: .continuous)
                    .stroke(AppTheme.accent.opacity(0.16), lineWidth: 1.5)
                RoundedRectangle(cornerRadius: size * 0.23, style: .continuous)
                    .trim(from: 0, to: max(0.02, min(1, ringFraction)))
                    .stroke(AppTheme.accent, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                    .rotationEffect(.degrees(-90))
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(progress?.stage.rawValue ?? (ringFraction == nil ? "待转写" : "已转写"))
        .accessibilityValue("\(Int((ringFraction ?? 0) * 100))%")
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
