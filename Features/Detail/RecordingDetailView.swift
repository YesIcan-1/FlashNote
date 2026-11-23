import AVFoundation
import SwiftUI
import FlashNoteCore
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// 录音详情是音频、全文和 AI 纪要的唯一聚合入口。
struct RecordingDetailView: View {
    private enum Section: String, CaseIterable, Identifiable {
        case transcript = "转写"
        case minutes = "纪要"
        case mindMap = "思维导图"
        case insight = "洞察"
        var id: Self { self }
    }

    let recording: Recording
    var onClose: (() -> Void)? = nil
    @Environment(\.appEnvironment) private var environment
    @Environment(\.dismiss) private var dismiss
    @State private var transcript: Transcript?
    @State private var minutes: Minutes?
    @State private var mindMap: Minutes?
    @State private var insight: Minutes?
    @State private var isGeneratingInsight = false
    @State private var isGeneratingMindMap = false
    @State private var insightError: String?
    @State private var mindMapError: String?
    @State private var selectedTemplateID = MinutesTemplate.defaultTemplate.id
    @State private var displayTitle: String?
    @State private var player = AudioPlayer()
    @State private var isRetranscribing = false
    @State private var transcriptionError: String?
    @State private var showingDeleteConfirmation = false
    @State private var wasDeleted = false
    @State private var deletionError: String?
    @State private var selectedSection: Section = .transcript
    @State private var transcriptQuery = ""
    @State private var recordingStatus: RecordingStatus?
    @State private var waveformSamples: [CGFloat] = []
    @State private var mindMapScale: CGFloat = 1
    @State private var editingTranscript = false
    @State private var transcriptDraft: [TranscriptSegment] = []
    @State private var editingMinutes = false
    @State private var minutesDraft: [MinutesSection] = []
    @State private var showingCalendarSheet = false
    @State private var calendarTodoTitle: String?
    @State private var todoDraft: [TodoDraft] = []
    @State private var todoEditRevision = 0
    @State private var editingTodoID: UUID?
    @FocusState private var focusedTodoID: UUID?
    @State private var contentMessage: String?
    @State private var exportDocument: RecordingTextDocument?
    @State private var exportContentType: UTType = .plainText
    @State private var exportFilename = "FlashNote"
    @State private var showingExporter = false
    private var processingActive: Bool { environment?.processing.progress[recording.id]?.isActive ?? false }
    private var isGeneratingMinutes: Bool { environment?.processing.progress[recording.id]?.stage == .minutes }

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
        .onChange(of: environment?.processing.revision) { _, _ in loadTranscript(); loadMinutes() }
        .sheet(isPresented: $showingCalendarSheet) {
            if let calendarTodoTitle {
                TodoCalendarSheet(title: calendarTodoTitle, recordingTitle: displayTitle ?? recording.title) { result in
                    switch result {
                    case .success: contentMessage = "已加入本机日历"
                    case .failure(let error): contentMessage = "加入日历失败：\(error.localizedDescription)"
                    }
                }
            }
        }
        .fileExporter(isPresented: $showingExporter, document: exportDocument,
                      contentType: exportContentType, defaultFilename: exportFilename) { result in
            switch result {
            case .success: contentMessage = "导出完成"
            case .failure(let error): contentMessage = "导出失败：\(error.localizedDescription)"
            }
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                audioCard
                if let progress = environment?.processing.progress[recording.id],
                   progress.stage == .needsConfiguration || progress.stage == .failed { processingCard(progress) }
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    Picker("内容", selection: $selectedSection) {
                        ForEach([Section.transcript, .minutes, .insight]) { section in
                            Text(section.rawValue).tag(section)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 300)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity)
                switch selectedSection {
                case .transcript: transcriptPanel
                case .minutes: minutesPanel
                case .mindMap: mindMapPanel
                case .insight: insightPanel
                }
                if let contentMessage { Text(contentMessage).font(.caption).foregroundStyle(AppTheme.secondaryText) }
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
                Text(displayTitle ?? recording.title)
                    .font(.system(size: 25, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 10) {
                    MetadataText(text: recording.createdAt.formatted(date: .abbreviated, time: .shortened))
                    MetadataText(text: RecordingRow.durationText(recording.duration))
                    RecordingStatusView(status: recordingStatus ?? recording.status)
                }
            }
            Spacer()
            if let progress = environment?.processing.progress[recording.id], progress.isActive {
                TaskProgressRing(fraction: progress.fraction, label: progress.stage.rawValue)
            }
            if let onClose {
                Button("返回", action: onClose).buttonStyle(.bordered)
            }
            Button(role: .destructive) { showingDeleteConfirmation = true } label: {
                Label("删除", systemImage: AppIcons.delete)
            }
            .buttonStyle(.bordered)
        }
    }

    private func processingCard(_ progress: ProcessingProgress) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    if progress.isActive { ProgressView().controlSize(.small) }
                    Text(progress.stage.rawValue).font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(progress.finishedSteps)/\(progress.totalSteps)")
                        .font(.caption.monospacedDigit()).foregroundStyle(AppTheme.secondaryText)
                }
                if let detail = progress.detail { Text(detail).font(.caption).foregroundStyle(AppTheme.secondaryText) }
                if progress.stage == .needsConfiguration || progress.stage == .failed {
                    if progress.totalSteps == 1 {
                        Button("重试生成纪要", action: generateMinutes).buttonStyle(.bordered)
                    } else {
                        Button("继续生成内容") { Task { await environment?.processing.generateAll(recordingID: recording.id) } }
                            .buttonStyle(.bordered)
                    }
                }
            }
        }
    }

    private var audioCard: some View {
        Card {
            VStack(spacing: 14) {
                HStack {
                    Text(AudioPlayer.formatTime(player.currentTime)).font(.caption.monospacedDigit())
                    Spacer()
                    Text(AudioPlayer.formatTime(max(player.duration, recording.duration))).font(.caption.monospacedDigit())
                }.foregroundStyle(AppTheme.secondaryText)
                #if os(macOS)
                if !waveformSamples.isEmpty {
                    AudioWaveform(samples: waveformSamples, progress: player.duration > 0 ? player.currentTime / player.duration : 0) { fraction in
                        player.seek(to: player.duration * fraction)
                    }
                    .frame(height: 76)
                }
                #endif
                Slider(
                    value: Binding(get: { player.currentTime }, set: { player.seek(to: $0) }),
                    in: 0...max(1, player.duration)
                )
                .accessibilityLabel("播放进度")
                HStack(spacing: 22) {
                    Spacer()
                    Button { player.skip(by: -10) } label: { Image(systemName: "gobackward.10") }
                        .buttonStyle(.borderless).accessibilityLabel("后退 10 秒")
                    IconButton(icon: player.isPlaying ? AppIcons.pause : AppIcons.play,
                               background: AppTheme.primaryText, size: 52) {
                        player.isPlaying ? player.pause() : player.play()
                    }
                    Button { player.skip(by: 10) } label: { Image(systemName: "goforward.10") }
                        .buttonStyle(.borderless).accessibilityLabel("前进 10 秒")
                    Spacer()
                    Button(String(format: "%gx", Double(player.playbackRate))) { player.cyclePlaybackRate() }
                        .buttonStyle(.borderless).accessibilityLabel("播放速度")
                }
            }
        }
    }

    @ViewBuilder
    private var transcriptPanel: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeading("全文转写", subtitle: transcript.map { "\($0.segments.count) 段 · \($0.fullText.count) 字" } ?? "尚未生成") {
                    HStack(spacing: 10) {
                        if let transcript {
                            Button("复制") { copyText(RecordingContent.transcriptText(transcript)) }
                            Button("导出") { presentExport(RecordingContent.transcriptText(transcript), type: .plainText, suffix: "转写") }
                            Button(editingTranscript ? "取消" : "编辑") {
                                editingTranscript ? cancelTranscriptEdit() : beginTranscriptEdit()
                            }
                            if editingTranscript {
                                Button("保存修改") { commitTranscriptEdit() }.fontWeight(.semibold)
                            }
                        }
                    }.buttonStyle(.borderless)
                }
                if let transcript {
                    if editingTranscript {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(transcriptDraft.indices, id: \.self) { index in
                                HStack(alignment: .top, spacing: 16) {
                                    Text(timestampText(transcriptDraft[index].startTime))
                                        .font(.caption.monospacedDigit()).foregroundStyle(AppTheme.accent)
                                        .frame(width: 48, alignment: .leading)
                                    TextEditor(text: $transcriptDraft[index].text)
                                        .font(.body)
                                        .frame(minHeight: 64)
                                        .padding(5)
                                        .background(AppTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 8))
                                }
                                Divider()
                            }
                        }
                    } else {
                        HStack(spacing: 8) {
                            Image(systemName: AppIcons.search).foregroundStyle(AppTheme.secondaryText)
                            TextField("搜索转写关键词", text: $transcriptQuery).textFieldStyle(.plain)
                        }
                        .padding(10)
                        .background(AppTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 10))
                        if !transcriptQuery.isEmpty {
                            Text("找到 \(filteredSegments.count) 段匹配内容")
                                .font(.caption).foregroundStyle(AppTheme.secondaryText)
                        }
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(filteredSegments) { segment in
                                HStack(alignment: .top, spacing: 16) {
                                    Button(timestampText(segment.startTime)) { player.seek(to: segment.startTime) }
                                        .buttonStyle(.plain)
                                        .font(.caption.monospacedDigit().weight(.medium))
                                        .foregroundStyle(AppTheme.accent)
                                        .frame(width: 48, alignment: .leading)
                                        .accessibilityLabel("跳转至 \(timestampText(segment.startTime))")
                                    VStack(alignment: .leading, spacing: 5) {
                                        if let speaker = segment.speaker, !speaker.isEmpty {
                                            Text(speaker).font(.caption.weight(.semibold)).foregroundStyle(AppTheme.secondaryText)
                                        }
                                        Text(segment.text).font(.body)
                                            .textSelection(.enabled)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                                .padding(.vertical, 8)
                                Divider()
                            }
                        }
                        if filteredSegments.isEmpty {
                            Text("没有匹配的转写内容").font(.body).foregroundStyle(AppTheme.secondaryText)
                                .padding(.vertical, 16)
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
                Divider()
                if isRetranscribing { ProgressView("正在重新转写…") }
                Button(isRetranscribing ? "转写中…" : (transcript == nil ? "开始转写" : "重新转写")) { retranscribe() }
                    .buttonStyle(.borderedProminent)
                    .disabled(isRetranscribing || recording.audioFilename == nil || processingActive || editingTranscript)
            }
        }
    }

    @ViewBuilder
    private var minutesPanel: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeading("AI 纪要", subtitle: "基于当前全文生成") {
                    HStack(spacing: 10) {
                        if let minutes {
                            Button("复制") { copyText(RecordingContent.minutesMarkdown(minutes)) }
                            Button("导出") { presentExport(RecordingContent.minutesMarkdown(minutes), type: UTType(filenameExtension: "md") ?? .plainText, suffix: "纪要") }
                            Button(editingMinutes ? "取消" : "编辑") {
                                editingMinutes ? cancelMinutesEdit() : beginMinutesEdit()
                            }
                            if editingMinutes {
                                Button("保存修改") { commitMinutesEdit() }.fontWeight(.semibold)
                            }
                        }
                    }.buttonStyle(.borderless)
                }
                if let minutes {
                    VStack(alignment: .leading, spacing: 14) {
                        if editingMinutes {
                            ForEach(minutesDraft.indices.filter { minutesDraft[$0].title != "待办" }, id: \.self) { index in
                                VStack(alignment: .leading, spacing: 7) {
                                    Text(minutesDraft[index].title).font(.body.weight(.semibold))
                                    TextEditor(text: $minutesDraft[index].body)
                                        .font(.body)
                                        .frame(minHeight: max(92, CGFloat(minutesDraft[index].body.components(separatedBy: .newlines).count) * 25))
                                        .padding(6)
                                        .background(AppTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 8))
                                }
                            }
                        } else {
                            ForEach(minutes.sections.filter { $0.title != "待办" }, id: \.title) { section in
                                VStack(alignment: .leading, spacing: 7) {
                                    if minutes.templateID == MinutesTemplate.defaultTemplate.id && section.title == "会议主题" {
                                        Text(section.body.isEmpty ? "未生成内容" : section.body)
                                            .font(.title2.weight(.bold))
                                            .textSelection(.enabled)
                                    } else {
                                        Text(section.title).font(.body.weight(.semibold))
                                        if section.title == "会议信息", let table = MeetingInfoTableView(source: section.body) {
                                            table
                                        } else {
                                            MarkdownBodyView(source: section.body.isEmpty ? "未生成内容" : section.body)
                                                .font(.body).textSelection(.enabled)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    Divider()
                    todoEditor
                } else {
                    Text("尚未生成 AI 纪要").font(.body.weight(.semibold))
                    Text("AI 会根据真实全文提炼摘要、结论和待办，而不是写入模板内容。")
                        .font(.subheadline).foregroundStyle(AppTheme.secondaryText)
                }
                Divider()
                Picker("纪要风格", selection: $selectedTemplateID) { ForEach(MinutesTemplate.builtins) { Text($0.name).tag($0.id) } }
                    .pickerStyle(.menu)
                if isGeneratingMinutes { ProgressView("正在生成纪要…") }
                Button(isGeneratingMinutes ? "生成中…" : (minutes == nil ? "生成 AI 纪要" : "重新生成")) { generateMinutes() }
                    .buttonStyle(.borderedProminent).disabled(isGeneratingMinutes || transcript == nil || processingActive)
            }
        }
    }

    private var todoEditor: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("待办").font(.body.weight(.semibold))
            if todoDraft.isEmpty {
                Text("暂无生成内容").font(.body).foregroundStyle(AppTheme.tertiaryText)
            }
            ForEach($todoDraft) { $todo in
                HStack(alignment: .top, spacing: 12) {
                    Button {
                        todo.isCompleted.toggle()
                        scheduleTodoSave()
                    } label: {
                        Image(systemName: todo.isCompleted ? "checkmark.square.fill" : "square")
                            .font(.system(size: 20))
                            .foregroundStyle(todo.isCompleted ? AppTheme.primaryText : AppTheme.tertiaryText)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                    .accessibilityLabel(todo.isCompleted ? "标记未完成" : "标记完成")
                    if todo.isCompleted {
                        Text(todo.title).font(.body).strikethrough()
                            .foregroundStyle(AppTheme.tertiaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    } else if editingTodoID == todo.id {
                        TextField("输入待办事项", text: $todo.title, axis: .vertical)
                            .textFieldStyle(.plain).font(.body).lineLimit(1...8)
                            .fixedSize(horizontal: false, vertical: true)
                            .focused($focusedTodoID, equals: todo.id)
                            .onAppear { focusedTodoID = todo.id }
                            .onChange(of: todo.title) { _, _ in scheduleTodoSave() }
                            .onSubmit {
                                saveTodos()
                                editingTodoID = nil
                            }
                    } else {
                        Text(todo.title).font(.body)
                            .foregroundStyle(AppTheme.primaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    Button {
                        if todo.isCompleted {
                            todo.isCompleted = false
                            scheduleTodoSave()
                        }
                        editingTodoID = todo.id
                    } label: { Image(systemName: "pencil") }
                        .buttonStyle(.plain)
                        .padding(.top, 3)
                        .foregroundStyle(AppTheme.tertiaryText)
                        .accessibilityLabel("编辑待办")
                    Button {
                        calendarTodoTitle = todo.title
                        saveTodos()
                        showingCalendarSheet = true
                    } label: { Image(systemName: "calendar.badge.plus") }
                        .buttonStyle(.plain)
                        .padding(.top, 3)
                        .foregroundStyle(AppTheme.secondaryText)
                        .disabled(todo.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityLabel("加入日历")
                    Button(role: .destructive) {
                        todoDraft.removeAll { $0.id == todo.id }
                        scheduleTodoSave()
                    } label: { Image(systemName: "trash") }
                        .buttonStyle(.plain)
                        .padding(.top, 3)
                        .foregroundStyle(AppTheme.tertiaryText)
                        .accessibilityLabel("删除待办")
                }
                .padding(.vertical, 5)
            }
            Button {
                let added = TodoDraft(title: "", isCompleted: false)
                todoDraft.append(added)
                editingTodoID = added.id
            } label: {
                Label("添加待办", systemImage: "plus")
                    .font(.body.weight(.medium))
                    .padding(.horizontal, 18).padding(.vertical, 10)
                    .background(AppTheme.elevatedSurface, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .onDisappear { saveTodos() }
    }

    #if os(macOS)
    @ViewBuilder
    private var mindMapPanel: some View {
        Card {
            VStack(alignment: .leading, spacing: 16) {
                SectionHeading("思维导图", subtitle: "横向浏览主题与分支，使用右侧按钮缩放") {
                    if mindMap != nil || minutes != nil {
                        HStack(spacing: 8) {
                            Button { mindMapScale = max(0.85, mindMapScale - 0.15) } label: { Image(systemName: "minus.magnifyingglass") }
                            Button { mindMapScale = 1 } label: { Image(systemName: "arrow.counterclockwise") }
                                .accessibilityLabel("重置缩放")
                            Button { mindMapScale = min(1.6, mindMapScale + 0.15) } label: { Image(systemName: "plus.magnifyingglass") }
                        }
                        .buttonStyle(.borderless)
                    }
                }
                if let map = mindMap ?? minutes {
                    let outline = MindMapOutline(minutes: map,
                        fallbackTitle: RecordingTitle.shortTitle(from: map) ?? displayTitle ?? recording.title)
                    ScrollView([.horizontal, .vertical]) {
                        MindMapContent(outline: outline, zoom: mindMapScale)
                            .fixedSize(horizontal: true, vertical: true)
                    }
                    .frame(minHeight: 420, maxHeight: 760)
                } else {
                    ContentUnavailableView("尚无思维导图", systemImage: "point.3.connected.trianglepath.dotted",
                        description: Text("转写完成后会自动提炼主题结构。"))
                }
                if let mindMapError { Text(mindMapError).font(.caption).foregroundStyle(AppTheme.destructive) }
                if isGeneratingMindMap { ProgressView("正在生成思维导图…") }
                Button(isGeneratingMindMap ? "生成中…" : (mindMap == nil ? "生成思维导图" : "重新生成")) { generateMindMap() }
                    .buttonStyle(.borderedProminent).disabled(isGeneratingMindMap || transcript == nil || processingActive)
            }
        }
    }

    @ViewBuilder
    private var insightPanel: some View {
        Card {
            VStack(alignment: .leading, spacing: 16) {
                SectionHeading("洞察", subtitle: "基于真实全文提炼观点与启发") {
                    Image(systemName: AppIcons.sparkle).foregroundStyle(AppTheme.accent)
                }
                if let insight {
                    ForEach(insight.sections, id: \.title) { section in
                        VStack(alignment: .leading, spacing: 7) {
                            Text(section.title).font(.headline)
                            MarkdownBodyView(source: section.body.isEmpty ? "未生成内容" : section.body)
                                .font(.body).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.vertical, 8)
                        Divider()
                    }
                    Text("内容由 AI 生成，请对照“转写”核查关键事实。")
                        .font(.caption).foregroundStyle(AppTheme.secondaryText)
                } else {
                    Text("尚未生成洞察").font(.headline)
                    Text("连接已配置的 AI 服务，从这段录音的真实转写中提炼观点和启发。")
                        .font(.subheadline).foregroundStyle(AppTheme.secondaryText)
                }
                if let insightError { Text(insightError).font(.caption).foregroundStyle(AppTheme.destructive) }
                if isGeneratingInsight { ProgressView("正在生成洞察…") }
                Button(isGeneratingInsight ? "生成中…" : (insight == nil ? "生成洞察" : "重新生成")) { generateInsight() }
                    .buttonStyle(.borderedProminent)
                    .disabled(isGeneratingInsight || transcript == nil || processingActive)
            }
        }
    }
    #else
    private var mindMapPanel: some View { EmptyView() }
    private var insightPanel: some View { EmptyView() }
    #endif

    private func generateInsight() {
        guard let transcript, let store = environment?.store else { return }
        let settings = AppSettings(storeDirectory: AppEnvironment.defaultStoreDirectory())
        guard !settings.llmAPIKey.isEmpty, let baseURL = URL(string: settings.llmBaseURL) else {
            insightError = "请先在设置中填写 AI 纪要的 API 地址、模型和 API Key。"
            return
        }
        isGeneratingInsight = true; insightError = nil
        Task {
            do {
                let client = OpenAICompatibleClient(configuration: .init(baseURL: baseURL, apiKey: settings.llmAPIKey, model: settings.llmModel))
                let generated = try await MinutesGenerator(client: client).generate(transcript: transcript.fullText,
                                                                                  template: .insight,
                                                                                  recordingID: recording.id)
                try store.upsertMinutes(generated)
                insight = generated
            } catch { insightError = "生成失败：\(error.localizedDescription)" }
            isGeneratingInsight = false
        }
    }

    private func loadTranscript() {
        transcript = try? environment?.store.fetchTranscript(recordingID: recording.id)
        let latest = try? environment?.store.fetchRecording(id: recording.id)
        recordingStatus = latest?.status
        displayTitle = latest?.title
    }
    private var filteredSegments: [TranscriptSegment] {
        guard let transcript else { return [] }
        guard !transcriptQuery.isEmpty else { return transcript.segments }
        return transcript.segments.filter { $0.text.localizedCaseInsensitiveContains(transcriptQuery) }
    }
    private func loadMinutes() {
        let all = (try? environment?.store.fetchMinutes(recordingID: recording.id)) ?? []
        minutes = all.last(where: { $0.templateID != MinutesTemplate.insight.id && $0.templateID != MinutesTemplate.mindMap.id })
        mindMap = all.last(where: { $0.templateID == MinutesTemplate.mindMap.id })
        insight = all.last(where: { $0.templateID == MinutesTemplate.insight.id })
        if focusedTodoID == nil {
            todoDraft = minutes.map { RecordingContent.todoItems(from: $0).map(TodoDraft.init) } ?? []
        }
    }

    private func beginTranscriptEdit() {
        guard let transcript else { return }
        transcriptDraft = transcript.segments
        editingTranscript = true
    }

    private func cancelTranscriptEdit() {
        editingTranscript = false
        transcriptDraft = []
    }

    private func commitTranscriptEdit() {
        guard var transcript else { return }
        transcript.segments = transcriptDraft.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        saveTranscript(transcript)
        cancelTranscriptEdit()
    }

    private func beginMinutesEdit() {
        guard let minutes else { return }
        minutesDraft = minutes.sections
        editingMinutes = true
    }

    private func cancelMinutesEdit() {
        editingMinutes = false
        minutesDraft = []
    }

    private func commitMinutesEdit() {
        guard var minutes else { return }
        for section in minutesDraft where section.title != "待办" {
            if let index = minutes.sections.firstIndex(where: { $0.title == section.title }) {
                minutes.sections[index].body = section.body
            }
        }
        saveMinutes(minutes)
        cancelMinutesEdit()
    }

    private func saveTranscript(_ updated: Transcript) {
        do {
            try environment?.store.upsertTranscript(updated)
            transcript = updated
            contentMessage = "转写修改已保存；如需更新 AI 内容，请重新生成思维导图和洞察。"
        } catch { contentMessage = "保存转写失败：\(error.localizedDescription)" }
    }

    private func saveMinutes(_ updated: Minutes) {
        do {
            try environment?.store.upsertMinutes(updated)
            minutes = updated
            todoDraft = RecordingContent.todoItems(from: updated).map(TodoDraft.init)
            contentMessage = "纪要修改已保存"
        } catch { contentMessage = "保存纪要失败：\(error.localizedDescription)" }
    }

    private func saveTodos() {
        guard let minutes else { return }
        let items = todoDraft.map { RecordingTodo(title: $0.title, isCompleted: $0.isCompleted) }
        let updated = RecordingContent.updatingTodoItems(items, in: minutes)
        guard updated != minutes else { return }
        do {
            try environment?.store.upsertMinutes(updated)
            self.minutes = updated
        } catch { contentMessage = "保存待办失败：\(error.localizedDescription)" }
    }

    private func scheduleTodoSave() {
        todoEditRevision += 1
        let revision = todoEditRevision
        Task {
            try? await Task.sleep(nanoseconds: 650_000_000)
            guard revision == todoEditRevision else { return }
            saveTodos()
        }
    }

    private func presentExport(_ content: String, type: UTType, suffix: String) {
        exportDocument = RecordingTextDocument(text: content)
        exportContentType = type
        exportFilename = "\(displayTitle ?? recording.title)-\(suffix)"
        showingExporter = true
    }

    private func copyText(_ content: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(content, forType: .string)
        #else
        UIPasteboard.general.string = content
        #endif
        contentMessage = "已复制到剪贴板"
    }
    private func loadAudio() {
        guard let url = RecordingAssetService.audioURL(for: recording) else { return }
        player.load(url: url, fallbackDuration: recording.duration)
        #if os(macOS)
        Task.detached(priority: .utility) {
            let samples = (try? Self.readWaveform(at: url)) ?? []
            await MainActor.run { waveformSamples = samples }
        }
        #endif
    }

    private func generateMinutes() {
        guard let template = MinutesTemplate.builtins.first(where: { $0.id == selectedTemplateID }) else { return }
        environment?.processing.regenerateMinutes(recordingID: recording.id, template: template)
    }

    private func generateMindMap() {
        guard let transcript, let store = environment?.store else { return }
        let settings = AppSettings(storeDirectory: AppEnvironment.defaultStoreDirectory())
        guard !settings.llmAPIKey.isEmpty, let baseURL = URL(string: settings.llmBaseURL) else {
            mindMapError = "请先在设置中填写 AI 服务的 API 地址、模型和 API Key。"
            return
        }
        isGeneratingMindMap = true; mindMapError = nil
        Task {
            do {
                let client = OpenAICompatibleClient(configuration: .init(baseURL: baseURL, apiKey: settings.llmAPIKey, model: settings.llmModel))
                let generated = try await MinutesGenerator(client: client).generate(transcript: transcript.fullText,
                                                                                  template: .mindMap, recordingID: recording.id)
                try store.upsertMinutes(generated)
                mindMap = generated
            } catch { mindMapError = "生成失败：\(error.localizedDescription)" }
            isGeneratingMindMap = false
        }
    }

    private func retranscribe() {
        guard let store = environment?.store else { return }
        isRetranscribing = true; transcriptionError = nil
        environment?.processing.beginTranscription(recording.id)
        let settings = AppSettings(storeDirectory: AppEnvironment.defaultStoreDirectory())
        let service = RecordingTranscriptionService(store: store, engine: FileTranscriptionEngineFactory.make(settings: settings))
        Task {
            do {
                transcript = try await service.transcribe(recording)
                environment?.processing.transcriptionCompleted(recording.id)
                recordingStatus = (try? store.fetchRecording(id: recording.id))?.status
                loadMinutes()
                await environment?.processing.generateAll(recordingID: recording.id)
                loadTranscript(); loadMinutes()
            } catch TranscriptionError.engineUnavailable {
                transcriptionError = "当前转写引擎不可用，请在设置中选择可用服务后重试。"
                environment?.processing.transcriptionFailed(recording.id, error: TranscriptionError.engineUnavailable)
            } catch {
                transcriptionError = "转写失败：\(error.localizedDescription)"
                environment?.processing.transcriptionFailed(recording.id, error: error)
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

    #if os(macOS)
    nonisolated private static func readWaveform(at url: URL) throws -> [CGFloat] {
        let file = try AVAudioFile(forReading: url)
        guard file.length > 0 else { return [] }
        let count = 144
        var peaks = [Float](repeating: 0, count: count)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 8_192) else { return [] }
        var frameOffset: Int64 = 0
        while frameOffset < file.length {
            try file.read(into: buffer, frameCount: 8_192)
            guard buffer.frameLength > 0, let channels = buffer.floatChannelData else { break }
            for frame in stride(from: 0, to: Int(buffer.frameLength), by: 32) {
                let bucket = min(count - 1, Int((frameOffset + Int64(frame)) * Int64(count) / file.length))
                for channel in 0..<Int(buffer.format.channelCount) {
                    peaks[bucket] = max(peaks[bucket], abs(channels[channel][frame]))
                }
            }
            frameOffset += Int64(buffer.frameLength)
        }
        let maximum = peaks.max() ?? 0
        guard maximum > 0 else { return [CGFloat](repeating: 0.12, count: count) }
        return peaks.map { CGFloat(max(0.12, min(1, sqrt($0 / maximum)))) }
    }
    #endif
}

private struct TodoDraft: Identifiable, Equatable {
    let id: UUID
    var title: String
    var isCompleted: Bool

    init(id: UUID = UUID(), title: String, isCompleted: Bool) {
        self.id = id
        self.title = title
        self.isCompleted = isCompleted
    }

    init(_ item: RecordingTodo) {
        self.init(title: item.title, isCompleted: item.isCompleted)
    }
}

private struct MeetingInfoTableView: View {
    let rows: [[String]]

    init?(source: String) {
        let parsed = source.components(separatedBy: .newlines).compactMap { line -> [String]? in
            let cells = line.split(separator: "|", omittingEmptySubsequences: true)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard cells.count == 2 else { return nil }
            let separator = cells.allSatisfy { !$0.isEmpty && $0.allSatisfy { $0 == "-" || $0 == ":" } }
            return separator ? nil : cells
        }
        guard parsed.count >= 2 else { return nil }
        rows = parsed
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(rows.indices, id: \.self) { index in
                HStack(alignment: .top, spacing: 14) {
                    Text(rows[index][0]).font(index == 0 ? .body.weight(.semibold) : .body)
                        .frame(width: 120, alignment: .leading)
                    Text(rows[index][1]).font(index == 0 ? .body.weight(.semibold) : .body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .textSelection(.enabled)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(index == 0 ? AppTheme.elevatedSurface : Color.clear)
                if index < rows.count - 1 { Divider() }
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(AppTheme.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 9))
    }
}

#if os(macOS)
private struct AudioWaveform: View {
    let samples: [CGFloat]
    let progress: Double
    let seek: (Double) -> Void

    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                let slot = size.width / CGFloat(samples.count)
                for (index, amplitude) in samples.enumerated() {
                    let height = max(5, amplitude * size.height)
                    let rect = CGRect(x: CGFloat(index) * slot, y: (size.height - height) / 2,
                                      width: max(1, slot - 2), height: height)
                    context.fill(Path(roundedRect: rect, cornerRadius: slot / 2),
                                 with: .color(Double(index) / Double(samples.count) <= progress ? AppTheme.accent : AppTheme.border.opacity(0.9)))
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { location in
                seek(min(1, max(0, Double(location.x / max(1, geometry.size.width)))))
            }
        }
        .accessibilityLabel("音频波形，点击跳转播放位置")
    }
}

private struct MindMapContent: View {
    let outline: MindMapOutline
    let zoom: CGFloat
    private let colors: [Color] = [.purple, .blue, .green, .orange, .pink, .teal, .indigo]

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            Text(outline.title)
                .font(.system(size: 14 * zoom, weight: .semibold))
                .foregroundStyle(AppTheme.primaryText)
                .textSelection(.enabled)
                .frame(width: 180 * zoom, alignment: .leading)
                .padding(.horizontal, 15 * zoom).padding(.vertical, 11 * zoom)
                .background(AppTheme.accentMuted, in: RoundedRectangle(cornerRadius: 12 * zoom))
                .overlay(RoundedRectangle(cornerRadius: 12 * zoom).stroke(AppTheme.accent.opacity(0.6), lineWidth: 1.5))
            Rectangle().fill(AppTheme.accent).frame(width: 30 * zoom, height: 2)
            VStack(alignment: .leading, spacing: 14 * zoom) {
                ForEach(Array(outline.branches.enumerated()), id: \.element.id) { index, branch in
                    MindMapBranchView(node: branch, color: colors[index % colors.count], zoom: zoom)
                }
            }
            .overlay(alignment: .leading) {
                if outline.branches.count > 1 {
                    Rectangle().fill(AppTheme.accent.opacity(0.5))
                        .frame(width: 2)
                        .padding(.vertical, 22 * zoom)
                }
            }
        }
        .padding(30 * zoom)
    }
}

private struct MindMapBranchView: View {
    let node: MindMapNode
    let color: Color
    let zoom: CGFloat
    @State private var expanded = true

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            Rectangle().fill(color).frame(width: 26 * zoom, height: 2)
            HStack(alignment: .center, spacing: 5 * zoom) {
                Text(node.title)
                    .font(.system(size: 14 * zoom))
                    .foregroundStyle(AppTheme.primaryText)
                    .textSelection(.enabled)
                    .frame(width: 210 * zoom, alignment: .leading)
                if !node.children.isEmpty {
                    Button { expanded.toggle() } label: {
                        Image(systemName: expanded ? "chevron.left" : "chevron.right")
                            .font(.system(size: 11 * zoom, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(color)
                    .accessibilityLabel(expanded ? "收起\(node.title)" : "展开\(node.title)")
                }
            }
            .padding(.vertical, 7 * zoom)
            .padding(.leading, 10 * zoom)
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 3 * zoom)
            }
            if expanded && !node.children.isEmpty {
                Rectangle().fill(color).frame(width: 22 * zoom, height: 2)
                VStack(alignment: .leading, spacing: 10 * zoom) {
                    ForEach(node.children) { child in
                        MindMapBranchView(node: child, color: color.opacity(0.82), zoom: zoom)
                    }
                }
                .overlay(alignment: .leading) {
                    if node.children.count > 1 {
                        Rectangle().fill(color.opacity(0.55)).frame(width: 2)
                            .padding(.vertical, 18 * zoom)
                    }
                }
            }
        }
    }
}
#endif
