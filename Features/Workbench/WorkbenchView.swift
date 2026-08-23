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
    @State private var latestMinutesSummary: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                resumeSection
                minutesSection
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
            Button { openRecording(latest.id) } label: {
                Card {
                    HStack(spacing: 18) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 15, style: .continuous)
                                .fill(AppTheme.accentMuted)
                                .frame(width: 66, height: 66)
                            Image(systemName: AppIcons.mic)
                                .font(.title2.weight(.semibold))
                                .foregroundStyle(AppTheme.accent)
                        }
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
                }
            }
            .buttonStyle(.plain)
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
    private var minutesSection: some View {
        if let latestMinutesSummary {
            Button {
                if let latest = recordings.first { openRecording(latest.id) }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: AppIcons.sparkle)
                        .foregroundStyle(AppTheme.accent)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("AI 纪要已就绪").font(.subheadline.weight(.semibold))
                        Text(latestMinutesSummary)
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryText)
                            .lineLimit(2)
                    }
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .foregroundStyle(AppTheme.secondaryText)
                }
                .padding(16)
                .background(AppTheme.infoBackground, in: RoundedRectangle(cornerRadius: AppTheme.compactCornerRadius, style: .continuous))
            }
            .buttonStyle(.plain)
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
                            Button { openRecording(recording.id) } label: {
                                RecordingRow(recording: recording)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            if recording.id != recordings.prefix(5).last?.id { Divider() }
                        }
                    }
                }
            }
        }
    }

    private func reload() {
        recordings = (try? environment?.store.fetchRecordings()) ?? []
        latestMinutesSummary = recordings.lazy.compactMap { recording in
            guard recording.status == .summarized,
                  let minutes = try? environment?.store.fetchMinutes(recordingID: recording.id).last,
                  let first = minutes.sections.first?.body,
                  !first.isEmpty else { return nil }
            return first
        }.first
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
