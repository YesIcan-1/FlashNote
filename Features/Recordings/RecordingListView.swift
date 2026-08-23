import SwiftUI
import FlashNoteCore

/// 录音列表（macOS 中栏 / iPhone 录音页）。
/// 注意：核心包 Recording 不可哈希，iOS 导航用 UUID 值路由。
struct RecordingListView: View {
    @Environment(\.appEnvironment) private var environment
    @Binding var selectedID: UUID?
    @State private var recordings: [Recording] = []
    @State private var showingRecorder = false
    @State private var showingImport = false

    init(selectedID: Binding<UUID?>) {
        self._selectedID = selectedID
    }

    var body: some View {
        Group {
            if recordings.isEmpty {
                ContentUnavailableView("还没有录音", systemImage: AppIcons.mic,
                                       description: Text("点击 + 录音，或导入音频文件"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AppTheme.pageBackground)
            } else {
                List(selection: $selectedID) {
                    ForEach(recordings) { recording in
#if os(iOS)
                        NavigationLink(value: recording.id) {
                            RecordingRow(recording: recording)
                        }
#else
                        RecordingRow(recording: recording)
                            .tag(recording.id)
#endif
                    }
                }
                .scrollContentBackground(.hidden)
                .background(AppTheme.pageBackground)
            }
        }
        .navigationTitle("录音")
        .toolbar {
            ToolbarItemGroup {
                Button {
                    showingImport = true
                } label: {
                    Image(systemName: AppIcons.importFile)
                }
                .help("导入音频")
                Button {
                    showingRecorder = true
                } label: {
                    Image(systemName: AppIcons.plus)
                }
                .help("新建录音")
            }
        }
        .sheet(isPresented: $showingRecorder) {
            RecorderView()
        }
        .sheet(isPresented: $showingImport) {
            ImportAudioView()
        }
        .onAppear { reload() }
        .onChange(of: showingRecorder) { _, isShown in
            if !isShown { reload() }
        }
        .onChange(of: showingImport) { _, isShown in
            if !isShown { reload() }
        }
    }

    private func reload() {
        recordings = (try? environment?.store.fetchRecordings()) ?? []
    }
}
