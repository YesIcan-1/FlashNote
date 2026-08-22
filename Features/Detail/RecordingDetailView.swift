import SwiftUI
import FlashNoteCore

/// 录音详情。全文转写/播放可用；AI 纪要占位（M3 实现）。
struct RecordingDetailView: View {
    let recording: Recording
    @Environment(\.appEnvironment) private var environment
    @State private var transcript: Transcript?
    @State private var minutes: Minutes?
    @State private var isGeneratingMinutes = false
    @State private var minutesError: String?
    @State private var selectedTab: Tab = .transcript
    @State private var player = AudioPlayer()

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
        .task {
            loadTranscript()
            loadMinutes()
            if selectedTab == .player { loadAudio() }
        }
        .onChange(of: selectedTab) { _, newValue in
            if newValue == .player { loadAudio() }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch selectedTab {
        case .transcript:
            if let transcript {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(transcript.segments) { segment in
                            VStack(alignment: .leading, spacing: 2) {
                                if segment.startTime > 0 {
                                    Text(timestampText(segment.startTime))
                                        .font(.caption2)
                                        .foregroundStyle(AppTheme.secondaryText)
                                }
                                Text(segment.text)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
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
            minutesView
        case .player:
            playerView
        }
    }

    @ViewBuilder
    private var minutesView: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("纪要风格", selection: $selectedTemplateID) {
                ForEach(MinutesTemplate.builtins) { Text($0.name).tag($0.id) }
            }
            .pickerStyle(.segmented)
            if let minutes {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(minutes.sections, id: \.title) { section in
                            VStack(alignment: .leading, spacing: 5) {
                                Text(section.title).font(.headline)
                                Text(section.body.isEmpty ? "未生成内容" : section.body)
                            }
                        }
                    }
                }
            } else {
                ContentUnavailableView("尚未生成 AI 纪要", systemImage: AppIcons.sparkle,
                                       description: Text("选择风格后生成，可随时重新生成。"))
            }
            if let minutesError { Text(minutesError).font(.caption).foregroundStyle(AppTheme.destructive) }
            Button(isGeneratingMinutes ? "生成中…" : "生成 AI 纪要") { generateMinutes() }
                .buttonStyle(.borderedProminent).disabled(isGeneratingMinutes || transcript == nil)
        }
    }

    @State private var selectedTemplateID = MinutesTemplate.builtins[0].id

    @ViewBuilder
    private var playerView: some View {
        VStack(spacing: 14) {
            Text(AudioPlayer.formatTime(player.currentTime))
                .font(.system(size: 32, weight: .semibold, design: .rounded))
                .monospacedDigit()
            ProgressView(value: player.duration > 0 ? player.currentTime / player.duration : 0)
            HStack(spacing: 24) {
                IconButton(icon: player.isPlaying ? AppIcons.pause : AppIcons.play, size: 52) {
                    player.isPlaying ? player.pause() : player.play()
                }
                IconButton(icon: AppIcons.stop, color: .white, background: AppTheme.destructive) {
                    player.stop()
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func loadTranscript() {
        transcript = try? environment?.store.fetchTranscript(recordingID: recording.id)
    }

    private func loadMinutes() {
        minutes = try? environment?.store.fetchMinutes(recordingID: recording.id).last
    }

    private func generateMinutes() {
        guard let transcript, let store = environment?.store else { return }
        guard let template = MinutesTemplate.builtins.first(where: { $0.id == selectedTemplateID }) else { return }
        let settings = AppSettings(storeDirectory: AppEnvironment.defaultStoreDirectory())
        guard !settings.llmAPIKey.isEmpty, let baseURL = URL(string: settings.llmBaseURL) else {
            minutesError = "请先在设置中填写 API 地址、模型和 API Key。"
            return
        }
        isGeneratingMinutes = true; minutesError = nil
        Task {
            do {
                let client = OpenAICompatibleClient(configuration: .init(baseURL: baseURL, apiKey: settings.llmAPIKey, model: settings.llmModel))
                let generated = try await MinutesGenerator(client: client).generate(transcript: transcript.fullText, template: template, recordingID: recording.id)
                try store.upsertMinutes(generated)
                minutes = generated
            } catch {
                minutesError = "生成失败：\(error.localizedDescription)"
            }
            isGeneratingMinutes = false
        }
    }

    private func timestampText(_ t: TimeInterval) -> String {
        let total = Int(t)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    private func loadAudio() {
        guard let audioFilename = recording.audioFilename else { return }
        let url = AppEnvironment.defaultStoreDirectory()
            .appendingPathComponent("audio")
            .appendingPathComponent(audioFilename)
        player.load(url: url)
    }
}
