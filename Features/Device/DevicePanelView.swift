import SwiftUI
import FlashNoteCore
import CoreBluetooth

/// 设备面板：连接 QS668 录音笔、设备信息、文件列表、下载转写、录音控制。
struct DevicePanelView: View {
    @Environment(\.appEnvironment) private var environment
    @State private var viewModel: DeviceViewModel?
    @State private var isScanning = false

    var body: some View {
        Group {
            if let viewModel {
                content(viewModel)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("录音笔")
        .task {
            if let env = environment, viewModel == nil {
                viewModel = DeviceViewModel(store: env.store)
            }
        }
    }

    private func content(_ vm: DeviceViewModel) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            connectionBar(vm)
            Divider()
            if vm.phase == .connected {
                infoSection(vm)
                filesSection(vm)
            } else {
                scanSection(vm)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func connectionBar(_ vm: DeviceViewModel) -> some View {
        HStack {
            Circle()
                .fill(vm.phase == .connected ? AppTheme.success : (vm.phase == .error("") ? AppTheme.destructive : AppTheme.secondaryText))
                .frame(width: 10, height: 10)
            Text(vm.statusText)
                .foregroundStyle(AppTheme.secondaryText)
            Spacer()
        }
    }

    @ViewBuilder
    private func scanSection(_ vm: DeviceViewModel) -> some View {
        Button(vm.phase == .scanning ? "扫描中…" : "扫描设备") {
            isScanning = true
            vm.scan()
        }
        .buttonStyle(.borderedProminent)
        .disabled(vm.phase == .scanning)

        // 连接逻辑走 onConnected；这里展示发现的设备列表（从 central 回调填充）
        if !vm.discovered.isEmpty {
            Text("发现设备（点击连接）：")
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryText)
            ForEach(vm.discovered, id: \.identifier) { p in
                Button("连接 \(p.name ?? "CB08")") {
                    vm.connect(to: p)
                }
            }
        } else {
            Text("未发现设备。请确保录音笔已开机并处于广播状态（关闭其他占用 App，如声云语音转写）。")
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryText)
        }
    }

    @ViewBuilder
    private func infoSection(_ vm: DeviceViewModel) -> some View {
        HStack(spacing: 16) {
            StatBox(label: "电量", value: vm.battery.map { "\($0)%" } ?? "—")
            StatBox(label: "固件", value: vm.firmware ?? "—")
            StatBox(label: "文件", value: "\(vm.files.count)")
            Button("刷新") { vm.refreshInfo() }
                .buttonStyle(.bordered)
        }
        HStack(spacing: 12) {
            Button("开始录音") { vm.recordStart() }
            Button("保存") { vm.recordSave() }
            Button("实时推流") { vm.realtimeStart() }
            Button("停止流") { vm.realtimeStop() }
        }
        .buttonStyle(.bordered)
    }

    @ViewBuilder
    private func filesSection(_ vm: DeviceViewModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("设备文件")
                .font(.headline)
            if vm.files.isEmpty {
                Text("暂无文件")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
            } else {
                ForEach(Array(vm.files.enumerated()), id: \.offset) { _, file in
                    HStack {
                        Text(file.name)
                            .lineLimit(1)
                        Spacer()
                        Text("\(file.size) B")
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryText)
                        Button("下载转写") { vm.downloadAndTranscribe(file: file) }
                            .buttonStyle(.bordered)
                    }
                }
                .font(.callout)
            }
        }
    }
}

/// 设备信息统计卡。
struct StatBox: View {
    let label: String
    let value: String
    var body: some View {
        VStack {
            Text(value).font(.title3.bold())
            Text(label).font(.caption).foregroundStyle(AppTheme.secondaryText)
        }
        .padding(12)
        .background(AppTheme.background, in: RoundedRectangle(cornerRadius: 10))
    }
}
