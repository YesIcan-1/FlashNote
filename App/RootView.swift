import SwiftUI
import FlashNoteCore

/// 侧边栏固定项（与录音 UUID 区分，用于路由内容区）。
enum SidebarItem: Hashable {
    case recordings
    case device
}

struct RootView: View {
    @Environment(\.appEnvironment) private var environment
    @State private var recordings: [Recording] = []
    @State private var selection: UUID?
    @State private var showingSettings = false
    @State private var sidebarItem: SidebarItem = .recordings

    var body: some View {
#if os(macOS)
        NavigationSplitView {
            List(selection: $sidebarItem) {
                Label("所有录音", systemImage: AppIcons.mic)
                    .fontWeight(.semibold)
                    .tag(SidebarItem.recordings)
                Label("录音笔", systemImage: AppIcons.settings)
                    .tag(SidebarItem.device)
                Label("工作", systemImage: AppIcons.folder)
                    .foregroundStyle(.secondary)
                    .disabled(true)
                Label("课程", systemImage: AppIcons.book)
                    .foregroundStyle(.secondary)
                    .disabled(true)
                Label("会议", systemImage: AppIcons.chat)
                    .foregroundStyle(.secondary)
                    .disabled(true)
                Text("文件夹筛选将在 M4 提供")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.secondaryText)
            }
            .navigationTitle("FlashNote")
            .listStyle(.sidebar)
            .toolbar {
                ToolbarItem {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: AppIcons.settings)
                    }
                    .help("设置")
                }
            }
        } content: {
            switch sidebarItem {
            case .recordings:
                RecordingListView(selectedID: $selection)
            case .device:
                DevicePanelView()
            }
        } detail: {
            if let selection,
               let recording = recordings.first(where: { $0.id == selection }) {
                RecordingDetailView(recording: recording)
                    .id(recording.id)
            } else {
                ContentUnavailableView("选择一条录音", systemImage: AppIcons.document)
            }
        }
        .frame(minWidth: 1000, minHeight: 620)
        .onChange(of: selection) { _, _ in reloadRecordings() }
        .onChange(of: sidebarItem) { _, _ in reloadRecordings() }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
#else
        TabView {
            NavigationStack {
                RecordingListView(selectedID: $selection)
                    .navigationDestination(for: UUID.self) { id in
                        if let recording = recordings.first(where: { $0.id == id }) {
                            RecordingDetailView(recording: recording)
                        }
                    }
            }
            .tabItem { Label("录音", systemImage: AppIcons.mic) }
            ContentUnavailableView("文件夹将在 M4 实现", systemImage: AppIcons.folder)
                .tabItem { Label("文件夹", systemImage: AppIcons.folder) }
            DevicePanelView()
                .tabItem { Label("录音笔", systemImage: AppIcons.settings) }
            SettingsView()
                .tabItem { Label("设置", systemImage: AppIcons.settings) }
        }
#endif
    }

    private func reloadRecordings() {
        recordings = (try? environment?.store.fetchRecordings()) ?? []
    }
}
