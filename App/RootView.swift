import SwiftUI

/// 平台根视图：macOS 三栏 / iOS 标签栏。
struct RootView: View {
    var body: some View {
#if os(macOS)
        NavigationSplitView {
            Text("文件夹")
                .navigationTitle("FlashNote")
        } content: {
            Text("录音列表")
        } detail: {
            Text("详情")
        }
        .frame(minWidth: 900, minHeight: 600)
#else
        TabView {
            Text("录音")
                .tabItem { Label("录音", systemImage: "mic.fill") }
            Text("文件夹")
                .tabItem { Label("文件夹", systemImage: "folder.fill") }
            Text("设置")
                .tabItem { Label("设置", systemImage: "gearshape.fill") }
        }
#endif
    }
}
