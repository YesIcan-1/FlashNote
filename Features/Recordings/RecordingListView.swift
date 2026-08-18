import SwiftUI
import FlashNoteCore

/// 录音列表（macOS 中栏 / iPhone 录音页）。
/// 注意：核心包 Recording 不可哈希，iOS 导航用 UUID 值路由。
struct RecordingListView: View {
    @Environment(\.appEnvironment) private var environment
    @State private var recordings: [Recording] = []
    @State private var showingRecorder = false
    @State private var selectedID: UUID?

    var body: some View {
        Group {
            if recordings.isEmpty {
                ContentUnavailableView("还没有录音", systemImage: AppIcons.mic,
                                       description: Text("点击 + 开始第一次录音"))
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
            }
        }
        .navigationTitle("录音")
        .toolbar {
            ToolbarItem {
                Button {
                    showingRecorder = true
                } label: {
                    Image(systemName: AppIcons.plus)
                }
            }
        }
        .sheet(isPresented: $showingRecorder) {
            RecorderView()
        }
        .onAppear { reload() }
        .onChange(of: showingRecorder) { _, isShown in
            if !isShown { reload() }
        }
    }

    private func reload() {
        recordings = (try? environment?.store.fetchRecordings()) ?? []
    }
}
