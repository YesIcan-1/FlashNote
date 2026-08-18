import SwiftUI
import FlashNoteCore

struct RecordingRow: View {
    let recording: Recording

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(recording.title)
                    .font(.headline)
                    .foregroundStyle(AppTheme.primaryText)
                    .lineLimit(1)
                Spacer()
                RecordingStatusView(status: recording.status)
            }
            HStack(spacing: 12) {
                Label(recording.createdAt.formatted(date: .abbreviated, time: .shortened), systemImage: AppIcons.clock)
                Text(Self.durationText(recording.duration))
            }
            .font(.caption)
            .foregroundStyle(AppTheme.secondaryText)
        }
        .padding(.vertical, 4)
    }

    static func durationText(_ duration: TimeInterval) -> String {
        let total = Int(duration)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
