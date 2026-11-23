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
    @State private var pendingDeletionIDs: Set<UUID> = []
    @State private var selectingRecordings = false
    @State private var selectedRecordingIDs: Set<UUID> = []
    @State private var deletionMessage: String?

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
                if selectingRecordings {
                    List {
                        ForEach(recordings) { recording in
                            Button {
                                if !selectedRecordingIDs.insert(recording.id).inserted {
                                    selectedRecordingIDs.remove(recording.id)
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: selectedRecordingIDs.contains(recording.id) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(selectedRecordingIDs.contains(recording.id) ? AppTheme.accent : AppTheme.secondaryText)
                                    RecordingRow(recording: recording)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .background(AppTheme.pageBackground)
                } else {
                    List(selection: $selectedID) {
                        ForEach(recordings) { recording in
#if os(iOS)
                            NavigationLink(value: recording.id) {
                                RecordingRow(recording: recording)
                            }
#else
                            HStack {
                                RecordingRow(recording: recording).frame(maxWidth: .infinity, alignment: .leading)
                                Button(role: .destructive) { pendingDeletionIDs = [recording.id] } label: { Image(systemName: AppIcons.delete) }
                                    .buttonStyle(.borderless).accessibilityLabel("删除\(recording.title)")
                            }.tag(recording.id)
#endif
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .background(AppTheme.pageBackground)
                }
            }
        }
        .navigationTitle("录音")
        .toolbar {
            ToolbarItemGroup {
                if !recordings.isEmpty {
                    if selectingRecordings {
                        Button("删除所选", role: .destructive) { pendingDeletionIDs = selectedRecordingIDs }
                            .disabled(selectedRecordingIDs.isEmpty)
                    }
                    Button(selectingRecordings ? "完成" : "多选") {
                        selectingRecordings.toggle()
                        selectedRecordingIDs = []
                    }
                }
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
        .alert("删除本地录音？", isPresented: Binding(get: { !pendingDeletionIDs.isEmpty }, set: { if !$0 { pendingDeletionIDs = [] } })) {
            Button("删除", role: .destructive) { deletePendingRecordings() }
            Button("取消", role: .cancel) { pendingDeletionIDs = [] }
        } message: { Text("将删除所选 \(pendingDeletionIDs.count) 条本机录音及其音频和转写；录音笔上的源文件会保留。") }
        .overlay(alignment: .bottom) {
            if let deletionMessage { Text(deletionMessage).font(.caption).foregroundStyle(AppTheme.destructive).padding() }
        }
    }

    private func reload() {
        recordings = (try? environment?.store.fetchRecordings()) ?? []
    }

    private func deletePendingRecordings() {
        guard let store = environment?.store else { return }
        let ids = pendingDeletionIDs
        pendingDeletionIDs = []
        var failures = 0
        for recording in recordings where ids.contains(recording.id) {
            do { try RecordingAssetService.delete(recording, from: store) }
            catch { failures += 1 }
        }
        if let selectedID, ids.contains(selectedID) { self.selectedID = nil }
        selectingRecordings = false
        selectedRecordingIDs = []
        deletionMessage = failures == 0 ? nil : "有 \(failures) 条录音删除失败，请重试。"
        reload()
    }
}
