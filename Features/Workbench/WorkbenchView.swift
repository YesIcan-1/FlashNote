import SwiftUI
import FlashNoteCore

/// 默认工作台：聚焦最近的声音任务和下一步操作，而非功能宫格。
struct WorkbenchView: View {
    @Environment(\.appEnvironment) private var environment
    let openDevice: () -> Void
    let openRecording: (UUID) -> Void
    @State private var recordings: [Recording] = []
    @State private var showingRecorder = false
    @State private var showingImport = false
    @State private var pendingDeletion: Recording?
    @State private var deletionError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                #if os(macOS)
                audioActions
                #endif
                resumeSection
                recentSection
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .frame(maxWidth: 1120, alignment: .leading)
        }
        .background(AppTheme.pageBackground)
        .navigationTitle("工作台")
        .sheet(isPresented: $showingRecorder) { RecorderView() }
        .sheet(isPresented: $showingImport) { ImportAudioView() }
        .onAppear(perform: reload)
        .onChange(of: showingRecorder) { _, showing in if !showing { reload() } }
        .onChange(of: showingImport) { _, showing in if !showing { reload() } }
        .onChange(of: environment?.processing.revision) { _, _ in reload() }
        .alert("删除本地录音？", isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } })) {
            Button("删除", role: .destructive) { deletePendingRecording() }
            Button("取消", role: .cancel) { pendingDeletion = nil }
        } message: { Text("本机音频和转写将被删除；录音笔上的源文件会保留。") }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(todayText)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppTheme.secondaryText)
                Text(greeting)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.primaryText)
                Text("把声音变成清晰的记录与下一步。")
                    .foregroundStyle(AppTheme.secondaryText)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 10) {
                devicePill
                Button {
                    showingRecorder = true
                } label: {
                    Label("开始录音", systemImage: AppIcons.plus)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    #if os(macOS)
    private var audioActions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("从声音开始").font(.title3.weight(.bold))
            HStack(alignment: .top, spacing: 16) {
                audioAction(
                    title: "实时转写",
                    subtitle: "录音时显示识别文字，完成后保存音频与全文。",
                    icon: "waveform.badge.mic",
                    actionTitle: "开始转写"
                ) { showingRecorder = true }
                audioAction(
                    title: "导入音频",
                    subtitle: "将已有录音加入文件库，按当前转写设置生成全文。",
                    icon: "square.and.arrow.down",
                    actionTitle: "选择文件"
                ) { showingImport = true }
            }
        }
    }

    private func audioAction(
        title: String,
        subtitle: String,
        icon: String,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 18) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(AppTheme.primaryText)
                    .frame(width: 46, height: 46)
                    .background(AppTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 13))
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.title3.weight(.bold)).foregroundStyle(AppTheme.primaryText)
                    Text(subtitle).font(.subheadline).foregroundStyle(AppTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, minHeight: 152, alignment: .leading)
        }
    }
    #endif

    @ViewBuilder
    private var devicePill: some View {
        if let session = environment?.deviceSession, session.phase == .connected {
            StatusPill(title: "录音笔已连接", symbol: "dot.radiowaves.left.and.right", tone: .success)
        } else {
            Button(action: openDevice) {
                StatusPill(title: "连接录音笔", symbol: AppIcons.device, tone: .neutral)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("前往录音笔连接设备")
        }
    }

    @ViewBuilder
    private var resumeSection: some View {
        SectionHeading("继续处理", subtitle: recordings.isEmpty ? "从一段声音开始" : "上次打开的声音内容") {
            Button("导入文件") { showingImport = true }
                .buttonStyle(.borderless)
        }
        if let latest = recordings.first {
            Card {
                HStack {
                    Button { openRecording(latest.id) } label: {
                    HStack(spacing: 18) {
                        RecordingProgressIcon(recording: latest,
                            progress: environment?.processing.progress[latest.id],
                            size: 66, symbol: AppIcons.mic)
                        VStack(alignment: .leading, spacing: 7) {
                            HStack(spacing: 8) {
                                Text(latest.title)
                                    .font(.headline)
                                    .foregroundStyle(AppTheme.primaryText)
                                    .lineLimit(1)
                                RecordingStatusView(status: latest.status)
                            }
                            HStack(spacing: 10) {
                                MetadataText(text: RecordingRow.durationText(latest.duration))
                                MetadataText(text: latest.createdAt.formatted(date: .abbreviated, time: .shortened))
                            }
                            AudioStripe()
                                .frame(height: 18)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.tertiaryText)
                    }
                    }.buttonStyle(.plain)
                    Button(role: .destructive) { pendingDeletion = latest } label: {
                        Image(systemName: AppIcons.delete)
                    }.buttonStyle(.plain).accessibilityLabel("删除\(latest.title)")
                }
            }
        } else {
            Card {
                HStack(spacing: 14) {
                    Image(systemName: "waveform")
                        .font(.title2)
                        .foregroundStyle(AppTheme.accent)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("还没有录音内容").font(.headline)
                        Text("开始录音、导入音视频，或从录音笔同步文件。")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                    Spacer()
                    Button("连接录音笔", action: openDevice).buttonStyle(.bordered)
                }
            }
        }
    }

    @ViewBuilder
    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading("最近内容", subtitle: "\(recordings.count) 条录音") {
                EmptyView()
            }
            if recordings.isEmpty {
                ContentUnavailableView("还没有声音内容", systemImage: AppIcons.document,
                                       description: Text("创建录音、导入音视频，或从录音笔同步文件。"))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
                    .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(AppTheme.border, lineWidth: 1)
                    }
            } else {
                Card {
                    VStack(spacing: 0) {
                        ForEach(recordings.prefix(5)) { recording in
                            HStack {
                                Button { openRecording(recording.id) } label: {
                                    RecordingRow(recording: recording)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }.buttonStyle(.plain)
                                Button(role: .destructive) { pendingDeletion = recording } label: {
                                    Image(systemName: AppIcons.delete)
                                }.buttonStyle(.plain).accessibilityLabel("删除\(recording.title)")
                            }
                            if recording.id != recordings.prefix(5).last?.id { Divider() }
                        }
                    }
                }
            }
        }
    }

    private func reload() {
        recordings = (try? environment?.store.fetchRecordings()) ?? []
    }

    private func deletePendingRecording() {
        guard let recording = pendingDeletion, let store = environment?.store else { return }
        pendingDeletion = nil
        do { try RecordingAssetService.delete(recording, from: store); reload() }
        catch { deletionError = "删除失败：\(error.localizedDescription)" }
    }

    private var todayText: String {
        Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        if hour < 11 { return "早上好" }
        if hour < 18 { return "下午好" }
        return "晚上好"
    }
}

private struct AudioStripe: View {
    var body: some View {
        GeometryReader { proxy in
            HStack(alignment: .center, spacing: 3) {
                ForEach(0..<30, id: \.self) { index in
                    Capsule()
                        .fill(AppTheme.accent.opacity(index.isMultiple(of: 4) ? 0.8 : 0.3))
                        .frame(width: max(2, (proxy.size.width - 87) / 30), height: CGFloat(5 + ((index * 7) % 13)))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
