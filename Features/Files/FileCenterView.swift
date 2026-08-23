import SwiftUI
import FlashNoteCore

/// 本地录音与已连接录音笔文件的统一入口。
struct FileCenterView: View {
    enum Source: String, CaseIterable, Identifiable {
        case local = "本地文件"
        case device = "设备文件"
        var id: String { rawValue }
    }

    @Environment(\.appEnvironment) private var environment
    @State private var source: Source = .local
    @State private var query = ""
    @State private var recordings: [Recording] = []
    @State private var selectedRecording: Recording?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            if source == .local { localFiles } else { deviceFiles }
        }
        .padding(.horizontal, 28).padding(.vertical, 24)
        .frame(maxWidth: 1120, maxHeight: .infinity, alignment: .topLeading)
        .background(AppTheme.pageBackground)
        .navigationTitle("文件")
        .sheet(item: $selectedRecording) { recording in
            NavigationStack { RecordingDetailView(recording: recording) }
        }
        .onAppear(perform: reload)
        .onChange(of: source) { _, selected in
            if selected == .device { environment?.startDeviceSession().onAppear() }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("声音文件").font(.system(size: 28, weight: .bold, design: .rounded))
                    Text(source == .local ? "保存在本机的录音、全文与 AI 纪要" : "直接读取已连接录音笔中的文件")
                        .font(.subheadline).foregroundStyle(AppTheme.secondaryText)
                }
                Spacer()
                if source == .device, let session = environment?.deviceSession, session.phase == .connected {
                    StatusPill(title: session.battery.map { "设备电量 \($0)%" } ?? "设备已连接", symbol: "dot.radiowaves.left.and.right", tone: .success)
                }
            }
            HStack(spacing: 14) {
                Picker("来源", selection: $source) {
                    ForEach(Source.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).frame(width: 220)
                if source == .local {
                    HStack(spacing: 7) {
                        Image(systemName: AppIcons.search).foregroundStyle(AppTheme.secondaryText)
                        TextField("搜索录音与文件", text: $query).textFieldStyle(.plain)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(AppTheme.border) }
                    .frame(maxWidth: 340)
                }
                Spacer()
                Button(source == .local ? "刷新" : "刷新设备") {
                    if source == .local { reload() } else { environment?.deviceSession?.refreshInfo() }
                }.buttonStyle(.bordered)
            }
        }
    }

    @ViewBuilder
    private var localFiles: some View {
        if filteredRecordings.isEmpty {
            Card {
                VStack(spacing: 12) {
                    Image(systemName: AppIcons.files).font(.largeTitle).foregroundStyle(AppTheme.secondaryText)
                    Text(query.isEmpty ? "还没有本地文件" : "没有匹配的文件").font(.headline)
                    Text(query.isEmpty ? "从工作台开始录音、导入音视频，或下载设备录音。" : "请尝试其它关键词。")
                        .font(.subheadline).foregroundStyle(AppTheme.secondaryText)
                }.frame(maxWidth: .infinity).padding(.vertical, 36)
            }
        } else {
            Card(padding: 0) {
                VStack(spacing: 0) {
                    HStack {
                        Text("名称"); Spacer(); Text("大小 / 时长").frame(width: 150, alignment: .leading); Text("状态").frame(width: 96, alignment: .leading)
                    }
                    .font(.caption.weight(.semibold)).foregroundStyle(AppTheme.secondaryText)
                    .padding(.horizontal, 18).padding(.vertical, 12)
                    Divider()
                    ForEach(Array(filteredRecordings.enumerated()), id: \.element.id) { index, recording in
                        Button { selectedRecording = recording } label: { LocalFileRow(recording: recording) }
                            .buttonStyle(.plain)
                        if index < filteredRecordings.count - 1 { Divider().padding(.leading, 18) }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var deviceFiles: some View {
        if let session = environment?.deviceSession, session.phase == .connected {
            if session.files.isEmpty {
                Card {
                    VStack(spacing: 12) {
                        Image(systemName: AppIcons.files).font(.largeTitle).foregroundStyle(AppTheme.secondaryText)
                        Text("设备暂无文件").font(.headline)
                        Text("可点击“刷新设备”重新读取录音笔文件列表。")
                            .font(.subheadline).foregroundStyle(AppTheme.secondaryText)
                    }.frame(maxWidth: .infinity).padding(.vertical, 36)
                }
            } else {
                Card(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(session.files.enumerated()), id: \.offset) { index, file in
                            HStack(spacing: 12) {
                                Image(systemName: "waveform").foregroundStyle(AppTheme.accent)
                                    .frame(width: 34, height: 34).background(AppTheme.accentMuted, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(file.candidateNames.first ?? file.name).lineLimit(1)
                                    MetadataText(text: "\(displayDeviceFileSize(file.size)) · 设备录音")
                                }
                                Spacer()
                                if session.progress > 0 && session.progress < 1 { ProgressView(value: session.progress).frame(width: 90) }
                                Button("下载并转写") { session.downloadAndTranscribe(file: file) }.buttonStyle(.bordered)
                            }
                            .padding(.horizontal, 18).padding(.vertical, 14)
                            if index < session.files.count - 1 { Divider().padding(.leading, 18) }
                        }
                    }
                }
            }
        } else {
            Card {
                VStack(spacing: 12) {
                    Image(systemName: AppIcons.device).font(.largeTitle).foregroundStyle(AppTheme.accent)
                    Text("正在连接录音笔").font(.headline)
                    Text("如果设备已连接过，FlashNote 正在恢复连接；否则请前往“录音笔”扫描设备。")
                        .multilineTextAlignment(.center).font(.subheadline).foregroundStyle(AppTheme.secondaryText)
                }.frame(maxWidth: .infinity).padding(.vertical, 36)
            }
        }
    }

    private var filteredRecordings: [Recording] {
        guard !query.isEmpty else { return recordings }
        return recordings.filter { recording in
            recording.title.localizedCaseInsensitiveContains(query) || (recording.audioFilename?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }
    private func reload() { recordings = (try? environment?.store.fetchRecordings()) ?? [] }
}

private struct LocalFileRow: View {
    let recording: Recording
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "waveform").foregroundStyle(AppTheme.accent)
                .frame(width: 34, height: 34).background(AppTheme.accentMuted, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(recording.title).font(.body.weight(.medium)).lineLimit(1)
                MetadataText(text: recording.audioFilename ?? "未保存音频")
            }
            Spacer()
            VStack(alignment: .leading, spacing: 4) {
                MetadataText(text: localFileSize(recording))
                MetadataText(text: RecordingRow.durationText(recording.duration))
            }.frame(width: 150, alignment: .leading)
            RecordingStatusView(status: recording.status).frame(width: 96, alignment: .leading)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(AppTheme.tertiaryText)
        }
        .padding(.horizontal, 18).padding(.vertical, 14).contentShape(Rectangle())
    }
    private func localFileSize(_ recording: Recording) -> String {
        guard let filename = recording.audioFilename else { return "—" }
        let url = AppEnvironment.defaultStoreDirectory().appendingPathComponent("audio").appendingPathComponent(filename)
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        return size > 0 ? ByteCountFormatter.string(fromByteCount: size, countStyle: .file) : "—"
    }
}
