import SwiftUI
import FlashNoteCore

/// 录音详情。M1：全文转写页签可用；AI 纪要 / 播放为占位（M3/M2 实现）。
struct RecordingDetailView: View {
    let recording: Recording
    @Environment(\.appEnvironment) private var environment
    @State private var transcript: Transcript?
    @State private var selectedTab: Tab = .transcript

    enum Tab: String, CaseIterable, Identifiable {
        case transcript = "全文转写"
        case minutes = "AI 纪要"
        case player = "播放"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(recording.title)
                .font(.title2.bold())
            HStack(spacing: 12) {
                Text(recording.createdAt.formatted(date: .abbreviated, time: .shortened))
                Text(RecordingRow.durationText(recording.duration))
                RecordingStatusView(status: recording.status)
            }
            .font(.caption)
            .foregroundStyle(AppTheme.secondaryText)

            Picker("页签", selection: $selectedTab) {
                ForEach(Tab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)

            content
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task { loadTranscript() }
    }

    @ViewBuilder
    private var content: some View {
        switch selectedTab {
        case .transcript:
            if let transcript {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(transcript.segments) { segment in
                            Text(segment.text)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(12)
                }
                .background(AppTheme.background.opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                ContentUnavailableView("暂无转写", systemImage: AppIcons.document)
            }
        case .minutes:
            ContentUnavailableView("AI 纪要将在 M3 实现", systemImage: AppIcons.sparkle)
        case .player:
            ContentUnavailableView("播放器将在 M2 实现", systemImage: AppIcons.play)
        }
    }

    private func loadTranscript() {
        transcript = try? environment?.store.fetchTranscript(recordingID: recording.id)
    }
}
