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
    let openDevice: () -> Void
    @State private var source: Source = .local
    @State private var query = ""
    @State private var recordings: [Recording] = []
    @State private var selectedRecording: Recording?
    @State private var pendingLocalDeletionIDs: Set<UUID> = []
    @State private var pendingDeviceDeletionNames: Set<String> = []
    @State private var selectingFiles = false
    @State private var selectedLocalIDs: Set<UUID> = []
    @State private var selectedDeviceNames: Set<String> = []
    @State private var deletionMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                if source == .local { connectedDeviceBanner }
                if source == .local { localFiles } else { deviceFiles }
            }
            .padding(.horizontal, 28).padding(.vertical, 24)
            .frame(maxWidth: 1120, alignment: .leading)
        }
        .background(AppTheme.pageBackground)
        .navigationTitle("文件")
        .sheet(item: $selectedRecording) { recording in
            NavigationStack {
                RecordingDetailView(recording: recording, onClose: { selectedRecording = nil })
            }
            #if os(macOS)
            .frame(minWidth: 760, minHeight: 640)
            #endif
        }
        .onAppear(perform: reload)
        .onChange(of: selectedRecording) { _, selected in
            if selected == nil { reload() }
        }
        .onChange(of: environment?.processing.revision) { _, _ in reload() }
        .onChange(of: source) { _, selected in
            selectingFiles = false
            selectedLocalIDs = []
            selectedDeviceNames = []
            if selected == .device { environment?.startDeviceSession().onAppear() }
        }
        .alert("删除本地录音？", isPresented: Binding(get: { !pendingLocalDeletionIDs.isEmpty }, set: { if !$0 { pendingLocalDeletionIDs = [] } })) {
            Button("删除", role: .destructive) { deleteLocalRecordings() }
            Button("取消", role: .cancel) { pendingLocalDeletionIDs = [] }
        } message: { Text("将删除所选 \(pendingLocalDeletionIDs.count) 条本机录音及其音频和转写；录音笔上的源文件会保留。") }
        .confirmationDialog("删除设备文件？", isPresented: Binding(get: { !pendingDeviceDeletionNames.isEmpty }, set: { if !$0 { pendingDeviceDeletionNames = [] } })) {
            Button("删除设备文件", role: .destructive) {
                if let session = environment?.deviceSession {
                    session.deleteFiles(session.files.filter { pendingDeviceDeletionNames.contains($0.displayName) })
                }
                pendingDeviceDeletionNames = []
                selectedDeviceNames = []
                selectingFiles = false
            }
        } message: { Text("将永久删除录音笔上所选 \(pendingDeviceDeletionNames.count) 个文件，本机副本会保留。") }
    }

    @ViewBuilder
    private var connectedDeviceBanner: some View {
        if let session = environment?.deviceSession, session.phase == .connected {
            Card {
                HStack(spacing: 14) {
                    Image(systemName: AppIcons.device)
                        .foregroundStyle(AppTheme.accent)
                        .frame(width: 42, height: 42)
                        .background(AppTheme.accentMuted, in: RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("录音笔已连接").font(.headline)
                        Text("\(session.files.count) 个设备文件 · 电量 \(session.battery.map { "\($0)%" } ?? "读取中")")
                            .font(.caption).foregroundStyle(AppTheme.secondaryText)
                    }
                    Spacer()
                    Button("查看设备文件") { source = .device }.buttonStyle(.bordered)
                }
            }
        } else {
            Card {
                HStack(spacing: 14) {
                    Image(systemName: AppIcons.device)
                        .foregroundStyle(AppTheme.primaryText)
                        .frame(width: 42, height: 42)
                        .background(AppTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("从录音笔同步").font(.headline)
                        Text("连接设备后查看录音并下载到本机。")
                            .font(.caption).foregroundStyle(AppTheme.secondaryText)
                    }
                    Spacer()
                    Button("连接设备", action: openDevice).buttonStyle(.bordered)
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(source == .local ? "全部文件（\(recordings.count)）" : "设备文件（\(environment?.deviceSession?.files.count ?? 0)）")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    Text(source == .local ? "保存在本机的录音与全文" : "列表显示设备内压缩大小；本地音频大小会因解码而不同")
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
                if selectingFiles {
                    Text("已选 \(source == .local ? selectedLocalIDs.count : selectedDeviceNames.count) 个")
                        .font(.caption).foregroundStyle(AppTheme.secondaryText)
                    Button("删除所选", role: .destructive) {
                        if source == .local { pendingLocalDeletionIDs = selectedLocalIDs }
                        else { pendingDeviceDeletionNames = selectedDeviceNames }
                    }
                    .disabled(source == .local ? selectedLocalIDs.isEmpty :
                        (selectedDeviceNames.isEmpty || environment?.deviceSession?.isDeletingFiles == true))
                }
                Button(selectingFiles ? "完成" : "多选") {
                    selectingFiles.toggle()
                    selectedLocalIDs = []
                    selectedDeviceNames = []
                }
                .buttonStyle(.bordered)
                Button(source == .local ? "刷新" : "刷新设备") {
                    if source == .local { reload() } else { environment?.deviceSession?.refreshInfo() }
                }.buttonStyle(.bordered)
            }
            if let deletionMessage { Text(deletionMessage).font(.caption).foregroundStyle(AppTheme.destructive) }
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
#if os(iOS)
            LazyVStack(spacing: 12) {
                ForEach(filteredRecordings) { recording in
                    localFileRow(recording)
                }
            }
#else
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 350, maximum: 520), spacing: 14)], spacing: 14) {
                ForEach(filteredRecordings) { recording in
                    localFileRow(recording)
                }
            }
#endif
        }
    }

    private func localFileRow(_ recording: Recording) -> some View {
        LocalFileRow(recording: recording,
                     isSelecting: selectingFiles,
                     isSelected: selectedLocalIDs.contains(recording.id),
                     open: {
                         if selectingFiles {
                             if !selectedLocalIDs.insert(recording.id).inserted { selectedLocalIDs.remove(recording.id) }
                         } else { selectedRecording = recording }
                     },
                     delete: { pendingLocalDeletionIDs = [recording.id] })
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
                                if selectingFiles {
                                    Image(systemName: selectedDeviceNames.contains(file.displayName) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(selectedDeviceNames.contains(file.displayName) ? AppTheme.accent : AppTheme.secondaryText)
                                }
                                Image(systemName: "waveform").foregroundStyle(AppTheme.accent)
                                    .frame(width: 34, height: 34).background(AppTheme.accentMuted, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(file.displayName).lineLimit(1)
                                    MetadataText(text: "设备压缩文件 \(displayDeviceFileSize(file.size))")
                                }
                                Spacer()
                                if session.isDownloaded(file) { Label("已下载", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(AppTheme.success) }
                                if session.activeDownloadIndex == index { TaskProgressRing(fraction: session.progress, label: session.statusText) }
                                if !selectingFiles {
                                    Button("下载并转写") { session.downloadAndTranscribe(file: file, index: index) }
                                        .buttonStyle(.bordered).disabled(session.activeDownloadFile != nil)
                                    Button(role: .destructive) { pendingDeviceDeletionNames = [file.displayName] } label: { Image(systemName: AppIcons.delete) }
                                        .buttonStyle(.borderless).accessibilityLabel("删除设备文件")
                                        .disabled(session.isDeletingFiles || session.activeDownloadFile != nil)
                                }
                            }
                            .padding(.horizontal, 18).padding(.vertical, 14)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if selectingFiles {
                                    if !selectedDeviceNames.insert(file.displayName).inserted {
                                        selectedDeviceNames.remove(file.displayName)
                                    }
                                }
                            }
                            if index < session.files.count - 1 { Divider().padding(.leading, 18) }
                        }
                    }
                }
            }
        } else {
            Card {
                VStack(spacing: 12) {
                    Image(systemName: AppIcons.device).font(.largeTitle).foregroundStyle(AppTheme.accent)
                    Text("尚未连接录音笔").font(.headline)
                    Text("在录音笔页扫描并连接设备，再回来查看文件。")
                        .multilineTextAlignment(.center).font(.subheadline).foregroundStyle(AppTheme.secondaryText)
                    Button("打开录音笔", action: openDevice).buttonStyle(.borderedProminent)
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

    private func deleteLocalRecordings() {
        guard let store = environment?.store else { return }
        let ids = pendingLocalDeletionIDs
        pendingLocalDeletionIDs = []
        var failures = 0
        for recording in recordings where ids.contains(recording.id) {
            do { try RecordingAssetService.delete(recording, from: store) }
            catch { failures += 1 }
        }
        selectedLocalIDs = []
        selectingFiles = false
        deletionMessage = failures == 0 ? nil : "有 \(failures) 条录音删除失败，请重试。"
        reload()
    }
}

private struct LocalFileRow: View {
    let recording: Recording
    let isSelecting: Bool
    let isSelected: Bool
    let open: () -> Void
    let delete: () -> Void
    @Environment(\.appEnvironment) private var environment
    var body: some View {
        Button(action: open) {
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 10) {
                        if isSelecting {
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(isSelected ? AppTheme.accent : AppTheme.secondaryText)
                        }
                        RecordingProgressIcon(recording: recording,
                            progress: environment?.processing.progress[recording.id])
                        Text(recording.title).font(.headline).foregroundStyle(AppTheme.primaryText)
                            .lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                        if !isSelecting {
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold)).foregroundStyle(AppTheme.tertiaryText)
                        }
                    }
                    HStack(spacing: 12) {
                        MetadataText(text: RecordingRow.durationText(recording.duration))
                        MetadataText(text: "本地 \(localFileSize(recording))")
                        Spacer(minLength: 0)
                        RecordingStatusView(status: recording.status)
                    }
                    MetadataText(text: recording.createdAt.formatted(date: .abbreviated, time: .shortened))
                }
                .frame(maxWidth: .infinity, minHeight: 106, alignment: .leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) {
            if !isSelecting {
                Button(role: .destructive, action: delete) { Image(systemName: AppIcons.delete) }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppTheme.tertiaryText)
                    .accessibilityLabel("删除\(recording.title)")
                    .padding(27)
            }
        }
    }
}

private func localFileSize(_ recording: Recording) -> String {
    guard let filename = recording.audioFilename else { return "—" }
    let url = AppEnvironment.defaultStoreDirectory().appendingPathComponent("audio").appendingPathComponent(filename)
    let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
    return size > 0 ? ByteCountFormatter.string(fromByteCount: size, countStyle: .file) : "—"
}
