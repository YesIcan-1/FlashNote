import SwiftUI
import FlashNoteCore

/// 本地和云端来源的文件入口；云同步不可用时不会伪造远程结果。
struct FileCenterView: View {
    enum Source: String, CaseIterable, Identifiable {
        case local = "本地文件"
        case cloud = "iCloud 文件"
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

            if source == .cloud {
                ContentUnavailableView("iCloud 文件尚未连接", systemImage: "icloud.slash",
                                       description: Text("本地录音、导入与录音笔同步仍可正常使用。"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
    }

    private var filteredRecordings: [Recording] {
        guard !query.isEmpty else { return recordings }
        return recordings.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }
}
