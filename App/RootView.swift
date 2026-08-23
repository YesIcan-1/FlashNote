import SwiftUI
import FlashNoteCore

/// 侧边栏固定项（与录音 UUID 区分，用于路由内容区）。
enum SidebarItem: Hashable {
    case workbench
    case recordings
    case files
    case device
    case settings
}

private enum MobileTab: Hashable {
    case workbench
    case recordings
    case files
    case device
    case settings
}

struct RootView: View {
    @Environment(\.appEnvironment) private var environment
    @State private var recordings: [Recording] = []
    @State private var selection: UUID?
    @State private var sidebarItem: SidebarItem = .workbench
    @State private var mobileTab: MobileTab = .workbench
    @State private var mobileRecordingPath: [UUID] = []

    var body: some View {
#if os(macOS)
        NavigationSplitView {
            List(selection: $sidebarItem) {
                Label("工作台", systemImage: AppIcons.home)
                    .fontWeight(.semibold)
                    .tag(SidebarItem.workbench)
                Label("所有录音", systemImage: AppIcons.mic)
                    .tag(SidebarItem.recordings)
                Label("文件", systemImage: AppIcons.files)
                    .tag(SidebarItem.files)
                Label("录音笔", systemImage: AppIcons.device)
                    .tag(SidebarItem.device)
                Label("设置", systemImage: AppIcons.settings)
                    .tag(SidebarItem.settings)
            }
            .navigationTitle("FlashNote")
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .background(AppTheme.pageBackground)
        } detail: {
            switch sidebarItem {
            case .workbench:
                WorkbenchView(
                    openDevice: { sidebarItem = .device },
                    openRecording: { id in
                        selection = id
                        sidebarItem = .recordings
                    }
                )
            case .recordings:
                if let selection,
                   let recording = recordings.first(where: { $0.id == selection }) {
                    RecordingDetailView(recording: recording)
                        .id(recording.id)
                } else {
                    RecordingListView(selectedID: $selection)
                }
            case .files:
                FileCenterView()
            case .device:
                DevicePanelView()
            case .settings:
                SettingsView()
            }
        }
        .frame(minWidth: 1000, minHeight: 620)
        .onAppear(perform: reloadRecordings)
        .onChange(of: selection) { _, _ in reloadRecordings() }
        .onChange(of: sidebarItem) { _, _ in reloadRecordings() }
#else
        TabView(selection: $mobileTab) {
            NavigationStack {
                WorkbenchView(
                    openDevice: { mobileTab = .device },
                    openRecording: { id in
                        mobileTab = .recordings
                        mobileRecordingPath = [id]
                    }
                )
            }
            .tabItem { Label("工作台", systemImage: AppIcons.home) }
            .tag(MobileTab.workbench)
            NavigationStack(path: $mobileRecordingPath) {
                RecordingListView(selectedID: $selection)
                    .navigationDestination(for: UUID.self) { id in
                        if let recording = recordings.first(where: { $0.id == id }) {
                            RecordingDetailView(recording: recording)
                        }
                    }
            }
            .tabItem { Label("录音库", systemImage: AppIcons.mic) }
            .tag(MobileTab.recordings)
            NavigationStack { FileCenterView() }
                .tabItem { Label("文件", systemImage: AppIcons.files) }
                .tag(MobileTab.files)
            DevicePanelView()
                .tabItem { Label("录音笔", systemImage: AppIcons.device) }
                .tag(MobileTab.device)
            SettingsView()
                .tabItem { Label("设置", systemImage: AppIcons.settings) }
                .tag(MobileTab.settings)
        }
        .onAppear(perform: reloadRecordings)
#endif
    }

    private func reloadRecordings() {
        recordings = (try? environment?.store.fetchRecordings()) ?? []
    }
}
