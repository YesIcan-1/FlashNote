import SwiftUI
import FlashNoteCore
import CoreBluetooth

/// QS668 / CB08 的唯一设备会话入口。页面展示的每一项均来自 `DeviceViewModel` 实时状态。
struct DevicePanelView: View {
    @Environment(\.appEnvironment) private var environment
    @State private var isScanning = false
    @State private var filesPendingDeletion: [CB08FileEntry] = []
    @State private var showingDeleteConfirmation = false
    @State private var selectingDeviceFiles = false
    @State private var selectedDeviceNames: Set<String> = []

    var body: some View {
        Group {
            if let viewModel = environment?.deviceSession { content(viewModel) }
            else { ProgressView("正在准备录音笔…") }
        }
        .navigationTitle("录音笔")
        .task { environment?.startDeviceSession().onAppear() }
        .alert("删除设备文件？", isPresented: $showingDeleteConfirmation) {
            Button("删除", role: .destructive) {
                environment?.deviceSession?.deleteFiles(filesPendingDeletion)
                filesPendingDeletion = []
                selectedDeviceNames = []
                selectingDeviceFiles = false
            }
            Button("取消", role: .cancel) { filesPendingDeletion = [] }
        } message: {
            Text("将从录音笔中永久删除所选 \(filesPendingDeletion.count) 个文件，无法恢复。本地已下载的副本不会被删除。")
        }
    }

    private func content(_ vm: DeviceViewModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                deviceHeader(vm)
                if vm.phase == .connected { connectedContent(vm) }
                else { connectionContent(vm) }
            }
            .padding(.horizontal, 28).padding(.vertical, 24)
            .frame(maxWidth: 1120, alignment: .leading)
        }
        .background(AppTheme.pageBackground)
    }

    private func deviceHeader(_ vm: DeviceViewModel) -> some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(vm.phase == .connected ? AppTheme.successBackground : AppTheme.accentMuted)
                    .frame(width: 66, height: 66)
                Image(systemName: AppIcons.device).font(.system(size: 28, weight: .medium))
                    .foregroundStyle(vm.phase == .connected ? AppTheme.success : AppTheme.accent)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text("FlashNote 录音笔").font(.title2.weight(.bold))
                Text(vm.phase == .connected ? "设备状态已同步" : "连接后可同步录音和设备文件")
                    .font(.subheadline).foregroundStyle(AppTheme.secondaryText)
            }
            Spacer()
            StatusPill(title: vm.statusText, symbol: phaseSymbol(vm.phase), tone: phaseTone(vm.phase)).lineLimit(1)
            if vm.phase == .connected {
                Menu {
                    Button("刷新设备信息") { vm.refreshInfo() }
                    Button("断开连接", role: .destructive) { vm.disconnect() }
                } label: {
                    Label("高级设备操作", systemImage: "gearshape")
                }
                .buttonStyle(.bordered)
            }
        }
    }

    @ViewBuilder
    private func connectionContent(_ vm: DeviceViewModel) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 18) {
                Text("连接设备").font(.title3.weight(.bold))
                Text("首次连接时系统可能请求蓝牙授权。已连接过的设备会在你进入本页或设备文件页时恢复，不会在启动 App 时打扰你。")
                    .font(.subheadline).foregroundStyle(AppTheme.secondaryText)
                HStack(spacing: 10) {
                    Button(vm.phase == .scanning ? "正在扫描…" : "扫描录音笔") { isScanning = true; vm.scan() }
                        .buttonStyle(.borderedProminent).disabled(vm.phase == .scanning)
                    if !vm.discovered.isEmpty { Text("发现 \(vm.discovered.count) 台设备").font(.caption).foregroundStyle(AppTheme.secondaryText) }
                }
                if !vm.discovered.isEmpty {
                    Divider()
                    ForEach(vm.discovered, id: \.identifier) { peripheral in
                        HStack {
                            Image(systemName: "dot.radiowaves.left.and.right").foregroundStyle(AppTheme.accent)
                            Text(peripheral.name ?? "CB08 录音笔")
                            Spacer()
                            Button("连接") { vm.connect(to: peripheral) }.buttonStyle(.bordered)
                        }
                    }
                }
            }
        }
    }

    private func connectedContent(_ vm: DeviceViewModel) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            healthSection(vm); recordingSection(vm); filesSection(vm)
        }
    }

    private func healthSection(_ vm: DeviceViewModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading("设备概览", subtitle: "已连接设备的实时信息") { Button("刷新") { vm.refreshInfo() }.buttonStyle(.borderless) }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 142), spacing: 12)], spacing: 12) {
                DeviceMetric(icon: "battery.100", label: "电量", value: vm.battery.map { "\($0)%" } ?? "读取中")
                DeviceMetric(icon: "waveform", label: "录音状态", value: recordStateText(vm.recordState))
                DeviceMetric(icon: "folder", label: "设备文件", value: "\(vm.files.count) 个")
                DeviceMetric(icon: "cpu", label: "固件版本", value: vm.firmware ?? "读取中")
            }
        }
    }

    private func recordingSection(_ vm: DeviceViewModel) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("设备录音").font(.headline)
                        Text(vm.streamStartedRecording
                             ? "这段录音由推流启动；停止推流也会保存并结束录音。"
                             : "此固件从未录制状态开启推流会同时开始录音。")
                            .font(.caption).foregroundStyle(AppTheme.secondaryText)
                    }
                    Spacer()
                    StatusPill(title: recordStateText(vm.recordState), symbol: "record.circle", tone: recordStateTone(vm.recordState))
                }
                HStack(spacing: 10) {
                    Button("开始录音") { vm.recordStart() }.buttonStyle(.borderedProminent)
                        .disabled(vm.recordState == 1 || vm.isRealtimeActive || vm.isRealtimeStarting)
                    Button(vm.recordState == 3 ? "继续录音" : "暂停录音") { vm.recordPause(paused: vm.recordState != 3) }
                        .buttonStyle(.bordered).disabled(vm.recordState != 1 && vm.recordState != 3)
                    Button("停止并保存录音") { vm.recordSave() }.buttonStyle(.bordered)
                        .disabled(vm.recordState != 1 && vm.recordState != 3 && !vm.isRealtimeActive)
                    Spacer()
                    Button(vm.isRealtimeStarting ? "启动中…" : "开始实时推流") { vm.realtimeStart() }
                        .buttonStyle(.bordered).disabled(vm.isRealtimeStarting || vm.isRealtimeActive)
                    Button(vm.streamStartedRecording ? "结束推流与录音" : "停止推流") { vm.realtimeStop() }
                        .buttonStyle(.bordered).disabled(!vm.isRealtimeActive)
                }
                HStack(spacing: 10) {
                    Image(systemName: vm.isRealtimeActive ? "waveform" : "waveform.slash")
                        .foregroundStyle(vm.isRealtimeActive ? AppTheme.accent : AppTheme.secondaryText)
                    Text(vm.realtimeStatus)
                    if vm.realtimePackets > 0 {
                        Spacer()
                        Text(RecorderViewModel.formatElapsed(vm.realtimeSeconds))
                            .monospacedDigit()
                    }
                }
                .font(.caption).foregroundStyle(AppTheme.secondaryText)
                if let issue = vm.realtimeRecognitionIssue, vm.isRealtimeActive {
                    Label(issue, systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(AppTheme.warning)
                }
                if vm.isRealtimeActive {
                    LiveTranscriptView(segments: vm.realtimeSegments, partialText: vm.realtimePartialText)
                        .frame(minHeight: 150)
                }
            }
        }
    }

    @ViewBuilder
    private func filesSection(_ vm: DeviceViewModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading("设备文件", subtitle: "这里显示设备内压缩大小；下载后保存的 WAV 大小可能明显增加") {
                HStack(spacing: 10) {
                    if selectingDeviceFiles {
                        Text("已选 \(selectedDeviceNames.count) 个").font(.caption).foregroundStyle(AppTheme.secondaryText)
                        Button("删除所选", role: .destructive) {
                            filesPendingDeletion = vm.files.filter { selectedDeviceNames.contains($0.displayName) }
                            showingDeleteConfirmation = !filesPendingDeletion.isEmpty
                        }
                        .disabled(selectedDeviceNames.isEmpty || vm.isDeletingFiles || vm.activeDownloadFile != nil)
                    }
                    Button(selectingDeviceFiles ? "完成" : "多选") {
                        selectingDeviceFiles.toggle()
                        selectedDeviceNames = []
                    }
                    .disabled(vm.files.isEmpty || vm.isDeletingFiles)
                    Button("刷新文件") { vm.refreshInfo() }.buttonStyle(.borderless)
                }
            }
            if vm.files.isEmpty {
                Card { HStack(spacing: 12) { Image(systemName: AppIcons.files).foregroundStyle(AppTheme.secondaryText); Text("设备暂无文件，或正在读取文件列表。").foregroundStyle(AppTheme.secondaryText); Spacer() } }
            } else {
                Card(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(vm.files.enumerated()), id: \.offset) { index, file in
                            DeviceFileRow(
                                file: file,
                                progress: vm.activeDownloadIndex == index ? vm.progress : 0,
                                statusText: vm.statusText,
                                isActive: vm.activeDownloadIndex == index,
                                isDownloading: vm.activeDownloadFile != nil,
                                isDownloaded: vm.isDownloaded(file),
                                isSelecting: selectingDeviceFiles,
                                isSelected: selectedDeviceNames.contains(file.displayName),
                                toggleSelection: {
                                    if !selectedDeviceNames.insert(file.displayName).inserted {
                                        selectedDeviceNames.remove(file.displayName)
                                    }
                                },
                                download: { vm.downloadAndTranscribe(file: file, index: index) },
                                delete: {
                                    filesPendingDeletion = [file]
                                    showingDeleteConfirmation = true
                                }
                            )
                            if index < vm.files.count - 1 { Divider().padding(.leading, 18) }
                        }
                    }
                }
            }
        }
    }

    private func phaseTone(_ phase: DeviceViewModel.Phase) -> StatusPill.Tone {
        switch phase { case .connected: .success; case .error: .destructive; case .scanning, .connecting: .accent; case .idle: .neutral }
    }
    private func phaseSymbol(_ phase: DeviceViewModel.Phase) -> String {
        switch phase { case .connected: "checkmark.circle.fill"; case .error: "exclamationmark.triangle.fill"; case .scanning, .connecting: "dot.radiowaves.left.and.right"; case .idle: "circle.dashed" }
    }
}

private struct DeviceMetric: View {
    let icon: String; let label: String; let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon).foregroundStyle(AppTheme.accent)
            Text(value).font(.headline.monospacedDigit()).lineLimit(1)
            Text(label).font(.caption).foregroundStyle(AppTheme.secondaryText)
        }
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading).padding(15)
        .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppTheme.compactCornerRadius, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: AppTheme.compactCornerRadius, style: .continuous).stroke(AppTheme.border) }
    }
}

private struct DeviceFileRow: View {
    let file: CB08FileEntry; let progress: Double; let statusText: String; let isActive: Bool; let isDownloading: Bool; let isDownloaded: Bool
    let isSelecting: Bool; let isSelected: Bool; let toggleSelection: () -> Void
    let download: () -> Void; let delete: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 12) {
                if isSelecting {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? AppTheme.accent : AppTheme.secondaryText)
                }
                Image(systemName: "waveform").foregroundStyle(AppTheme.accent).frame(width: 28, height: 28).background(AppTheme.accentMuted, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 3) { Text(file.displayName).lineLimit(1); MetadataText(text: "设备压缩文件 \(displayDeviceFileSize(file.size))") }
                Spacer()
                if isDownloaded { Label("已下载", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(AppTheme.success) }
                if isActive { TaskProgressRing(fraction: progress, label: statusText) }
                if !isSelecting {
                    Button("下载并转写", action: download).buttonStyle(.bordered).disabled(isDownloading)
                    Button(role: .destructive, action: delete) { Image(systemName: AppIcons.delete) }
                        .buttonStyle(.bordered).accessibilityLabel("删除设备文件").disabled(isDownloading)
                }
            }
        }
        .padding(18)
        .contentShape(Rectangle())
        .onTapGesture { if isSelecting { toggleSelection() } }
    }
}

func recordStateText(_ state: UInt8?) -> String {
    switch state { case 1: "录制中"; case 2: "未录制"; case 3: "已暂停"; default: "读取中" }
}
private func recordStateTone(_ state: UInt8?) -> StatusPill.Tone {
    switch state { case 1: .accent; case 3: .warning; case 2: .neutral; default: .neutral }
}
func displayDeviceFileSize(_ bytes: UInt32) -> String { ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file) }
