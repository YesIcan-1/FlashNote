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

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("来源", selection: $source) {
                ForEach(Source.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 280)

            if source == .device {
                deviceFiles
            } else {
                List(filteredRecordings) { recording in
                    RecordingRow(recording: recording)
                }
                .searchable(text: $query, prompt: "搜索录音与文件")
            }
        }
        .padding(20)
        .navigationTitle("文件")
        .onAppear { recordings = (try? environment?.store.fetchRecordings()) ?? [] }
        .onChange(of: source) { _, selected in
            if selected == .device { environment?.startDeviceSession().onAppear() }
        }
    }

    @ViewBuilder
    private var deviceFiles: some View {
        let session = environment?.deviceSession
        if session?.phase != .connected {
            ContentUnavailableView("录音笔未连接", systemImage: AppIcons.device,
                                   description: Text("请先在“录音笔”页面连接设备，再回来刷新文件。"))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let files = session?.files, !files.isEmpty {
            List(files, id: \.name) { file in
                HStack {
                    VStack(alignment: .leading) { Text(file.candidateNames.first ?? file.name); Text(deviceFileSize(file.size)).font(.caption).foregroundStyle(AppTheme.secondaryText) }
                    Spacer()
                    Button("下载转写") { session?.downloadAndTranscribe(file: file) }
                }
            }
        } else {
            ContentUnavailableView("设备暂无文件", systemImage: AppIcons.files,
                                   description: Text("点击刷新读取录音笔文件列表。"))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var filteredRecordings: [Recording] {
        guard !query.isEmpty else { return recordings }
        return recordings.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }
}

private func deviceFileSize(_ bytes: UInt32) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
}
