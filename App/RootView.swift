import SwiftUI
import FlashNoteCore

/// 侧边栏固定项（与录音 UUID 区分，用于路由内容区）。
enum SidebarItem: Hashable {
    case workbench
    case recordings
    case files
    case device
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
    @State private var showingSettings = false
    @State private var sidebarItem: SidebarItem = .workbench
    @State private var mobileTab: MobileTab = .workbench

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
            case .workbench:
                WorkbenchView { sidebarItem = .device }
            case .recordings:
                RecordingListView(selectedID: $selection)
            case .files:
                FileCenterView()
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
        TabView(selection: $mobileTab) {
            NavigationStack {
                WorkbenchView { mobileTab = .device }
            }
            .tabItem { Label("工作台", systemImage: AppIcons.home) }
            .tag(MobileTab.workbench)
            NavigationStack {
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
#endif
    }

    private func reloadRecordings() {
        recordings = (try? environment?.store.fetchRecordings()) ?? []
    }
}
