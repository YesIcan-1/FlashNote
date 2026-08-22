import SwiftUI
import FlashNoteCore

/// 默认工作台：聚焦正在进行的声音任务和下一步操作，而非功能宫格。
struct WorkbenchView: View {
    @Environment(\.appEnvironment) private var environment
    let openDevice: () -> Void
    @State private var recordings: [Recording] = []
    @State private var showingRecorder = false
    @State private var showingImport = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                quickActions
                recentSection
            }
            .padding(24)
            .frame(maxWidth: 980, alignment: .leading)
        }
        .background(AppTheme.background.opacity(0.45))
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
                Text("把声音变成可行动的信息")
                    .font(.largeTitle.bold())
                    .foregroundStyle(AppTheme.primaryText)
                Text("从录音、导入或录音笔开始一项声音任务。")
                    .foregroundStyle(AppTheme.secondaryText)
            }
            Spacer()
            Button {
                showingRecorder = true
            } label: {
                Label("新建声音任务", systemImage: AppIcons.plus)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var quickActions: some View {
        HStack(spacing: 12) {
            WorkbenchAction(title: "实时转写", detail: "录音时即时校核", icon: AppIcons.mic) {
                showingRecorder = true
            }
            WorkbenchAction(title: "导入音视频", detail: "批量提取并转写", icon: AppIcons.importFile) {
                showingImport = true
            }
            WorkbenchAction(title: "录音笔", detail: "录音、同步与转写", icon: AppIcons.device) {
                openDevice()
            }
        }
    }

    @ViewBuilder
    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("最近内容").font(.title3.bold())
                Spacer()
                Text("\(recordings.count) 条录音")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
            }
            if recordings.isEmpty {
                ContentUnavailableView("还没有声音内容", systemImage: AppIcons.document,
                                       description: Text("创建录音、导入音视频，或从录音笔同步文件。"))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
                    .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                Card {
                    VStack(spacing: 0) {
                        ForEach(recordings.prefix(5)) { recording in
                            RecordingRow(recording: recording)
                                .frame(maxWidth: .infinity, alignment: .leading)
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
}

private struct WorkbenchAction: View {
    let title: String
    let detail: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(AppTheme.accent)
                Text(title).font(.headline).foregroundStyle(AppTheme.primaryText)
                Text(detail).font(.caption).foregroundStyle(AppTheme.secondaryText)
            }
            .frame(maxWidth: .infinity, minHeight: 104, alignment: .leading)
        }
        .buttonStyle(.plain)
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(AppTheme.accent.opacity(0.12))
        }
    }
}
