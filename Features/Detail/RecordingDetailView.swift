import SwiftUI
import FlashNoteCore

/// 录音详情是音频、全文和 AI 纪要的唯一聚合入口。
struct RecordingDetailView: View {
    let recording: Recording
    @Environment(\.appEnvironment) private var environment
    @Environment(\.dismiss) private var dismiss
    @State private var transcript: Transcript?
    @State private var minutes: Minutes?
    @State private var isGeneratingMinutes = false
    @State private var minutesError: String?
    @State private var selectedTemplateID = MinutesTemplate.builtins[0].id
    @State private var player = AudioPlayer()
    @State private var isRetranscribing = false
    @State private var transcriptionError: String?
    @State private var showingDeleteConfirmation = false
    @State private var wasDeleted = false
    @State private var deletionError: String?

    var body: some View {
        Group {
            if wasDeleted {
                ContentUnavailableView("录音已删除", systemImage: AppIcons.delete, description: Text("本地音频、全文和 AI 纪要已移除。"))
            } else {
                content
            }
        }
        .alert("删除本地录音？", isPresented: $showingDeleteConfirmation) {
            Button("删除", role: .destructive, action: deleteRecording)
            Button("取消", role: .cancel) {}
        } message: {
            Text("将删除本机音频、全文转写和全部 AI 纪要，无法恢复。设备上的原文件不会删除。")
        }
        .task { loadTranscript(); loadMinutes(); loadAudio() }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                audioCard
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 18) {
                        transcriptPanel.frame(maxWidth: .infinity, alignment: .topLeading)
                        minutesPanel.frame(width: 340, alignment: .topLeading)
                    }
                    VStack(alignment: .leading, spacing: 18) { transcriptPanel; minutesPanel }
                }
                if let deletionError { Text(deletionError).font(.caption).foregroundStyle(AppTheme.destructive) }
            }
            .padding(.horizontal, 28).padding(.vertical, 24)
            .frame(maxWidth: 1120, alignment: .leading)
        }
        .background(AppTheme.pageBackground)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                Text(recording.title).font(.system(size: 28, weight: .bold, design: .rounded))
                HStack(spacing: 10) {
                    MetadataText(text: recording.createdAt.formatted(date: .abbreviated, time: .shortened))
                    MetadataText(text: RecordingRow.durationText(recording.duration))
                    RecordingStatusView(status: recording.status)
                }
            }
            Spacer()
            Button(role: .destructive) { showingDeleteConfirmation = true } label: {
                Label("删除", systemImage: AppIcons.delete)
            }
            .buttonStyle(.bordered)
        }
    }

    private var audioCard: some View {
        Card {
            HStack(spacing: 16) {
                Image(systemName: AppIcons.mic).font(.title2).foregroundStyle(AppTheme.accent)
                    .frame(width: 52, height: 52).background(AppTheme.accentMuted, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 8) {
                    HStack { Text(AudioPlayer.formatTime(player.currentTime)).font(.headline.monospacedDigit()); Spacer(); MetadataText(text: AudioPlayer.formatTime(player.duration)) }
                    ProgressView(value: player.duration > 0 ? player.currentTime / player.duration : 0)
                }
                HStack(spacing: 10) {
                    IconButton(icon: player.isPlaying ? AppIcons.pause : AppIcons.play, size: 42) { player.isPlaying ? player.pause() : player.play() }
                    IconButton(icon: AppIcons.stop, color: .white, background: AppTheme.destructive, size: 42) { player.stop() }
                }
            }
        }
    }

    @ViewBuilder
    private var transcriptPanel: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeading("全文转写", subtitle: transcript.map { "\($0.segments.count) 段 · \($0.fullText.count) 字" } ?? "尚未生成") {
                    Button(isRetranscribing ? "转写中…" : "重新转写") { retranscribe() }
                        .buttonStyle(.borderless)
                        .disabled(isRetranscribing || recording.audioFilename == nil)
                }
                if let transcript {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(transcript.segments) { segment in
                            HStack(alignment: .top, spacing: 12) {
                                Text(timestampText(segment.startTime)).font(.caption.monospacedDigit()).foregroundStyle(AppTheme.accent).frame(width: 42, alignment: .leading)
                                Text(segment.text).frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("暂无全文转写").font(.headline)
                        Text("下载设备录音或导入音频后，可在这里查看真实的全文结果。")
                            .font(.subheadline).foregroundStyle(AppTheme.secondaryText)
                    }.padding(.vertical, 22)
                }
                if let transcriptionError { Text(transcriptionError).font(.caption).foregroundStyle(AppTheme.destructive) }
            }
        }
    }

    @ViewBuilder
    private var minutesPanel: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeading("AI 纪要", subtitle: "基于当前全文生成") { Image(systemName: AppIcons.sparkle).foregroundStyle(AppTheme.accent) }
                if let minutes {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(minutes.sections, id: \.title) { section in
                            VStack(alignment: .leading, spacing: 5) {
                                Text(section.title).font(.subheadline.weight(.semibold))
                                Text(section.body.isEmpty ? "未生成内容" : section.body).font(.subheadline)
                            }
                        }
                    }
                } else {
                    Text("尚未生成 AI 纪要").font(.headline)
                    Text("AI 会根据真实全文提炼摘要、结论和待办，而不是写入模板内容。")
                        .font(.subheadline).foregroundStyle(AppTheme.secondaryText)
                }
                Divider()
                Picker("纪要风格", selection: $selectedTemplateID) { ForEach(MinutesTemplate.builtins) { Text($0.name).tag($0.id) } }
                    .pickerStyle(.menu)
                if let minutesError { Text(minutesError).font(.caption).foregroundStyle(AppTheme.destructive) }
                Button(isGeneratingMinutes ? "生成中…" : (minutes == nil ? "生成 AI 纪要" : "重新生成")) { generateMinutes() }
                    .buttonStyle(.borderedProminent).disabled(isGeneratingMinutes || transcript == nil)
            }
        }
    }

    private func loadTranscript() { transcript = try? environment?.store.fetchTranscript(recordingID: recording.id) }
    private func loadMinutes() { minutes = try? environment?.store.fetchMinutes(recordingID: recording.id).last }
    private func loadAudio() {
        guard let url = RecordingAssetService.audioURL(for: recording) else { return }
        player.load(url: url)
    }

    private func generateMinutes() {
        guard let transcript, let store = environment?.store else { return }
        guard let template = MinutesTemplate.builtins.first(where: { $0.id == selectedTemplateID }) else { return }
        let settings = AppSettings(storeDirectory: AppEnvironment.defaultStoreDirectory())
        guard !settings.llmAPIKey.isEmpty, let baseURL = URL(string: settings.llmBaseURL) else {
            minutesError = "请先在设置中填写 AI 纪要的 API 地址、模型和 API Key。"
            return
        }
        isGeneratingMinutes = true; minutesError = nil
        Task {
            do {
                let client = OpenAICompatibleClient(configuration: .init(baseURL: baseURL, apiKey: settings.llmAPIKey, model: settings.llmModel))
                let generated = try await MinutesGenerator(client: client).generate(transcript: transcript.fullText, template: template, recordingID: recording.id)
                try store.upsertMinutes(generated)
                minutes = generated
            } catch { minutesError = "生成失败：\(error.localizedDescription)" }
            isGeneratingMinutes = false
        }
    }

    private func retranscribe() {
        guard let store = environment?.store else { return }
        isRetranscribing = true; transcriptionError = nil
        let settings = AppSettings(storeDirectory: AppEnvironment.defaultStoreDirectory())
        let service = RecordingTranscriptionService(store: store, engine: FileTranscriptionEngineFactory.make(settings: settings))
        Task {
            do {
                transcript = try await service.transcribe(recording)
                loadMinutes()
            } catch {
                transcriptionError = "转写失败：\(error.localizedDescription)"
            }
            isRetranscribing = false
        }
    }

    private func deleteRecording() {
        guard let store = environment?.store else { return }
        do {
            try RecordingAssetService.delete(recording, from: store)
            player.stop()
            wasDeleted = true
            dismiss()
        } catch {
            deletionError = "删除失败：\(error.localizedDescription)"
        }
    }

    private func timestampText(_ t: TimeInterval) -> String {
        let total = Int(t)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
