import Foundation
import FlashNoteCore
import CoreBluetooth

/// 设备面板状态机：扫描/连接/设备信息/文件列表/下载+转写/录音控制。
@Observable
final class DeviceViewModel {
    enum Phase: Equatable {
        case idle
        case scanning
        case connecting
        case connected
        case error(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var battery: Int?
    private(set) var firmware: String?
    private(set) var files: [CB08FileEntry] = []
    private(set) var statusText = "扫描以连接 CB08 录音笔"
    private(set) var progress: Double = 0
    private(set) var discovered: [CBPeripheral] = []

    private let central: CB08Central
    private let store: RecordingStore
    private var device: CB08Device?
    private var transcription: DeviceTranscriptionService?
    private var seq: UInt8 = 0

    init(store: RecordingStore) {
        self.central = CB08Central.shared
        self.store = store
        wireCentral()
    }

    func scan() {
        phase = .scanning
        statusText = "正在扫描…"
        central.scan()
    }

    func connect(to peripheral: CBPeripheral) {
        phase = .connecting
        statusText = "正在连接 \(peripheral.name ?? "CB08")…"
        central.connect(peripheral)
    }

    func disconnect() {
        central.disconnect()
        device = nil
        transcription = nil
        phase = .idle
        files = []
        battery = nil
        firmware = nil
        statusText = "已断开，可重新扫描连接"
    }

    /// 视图出现时重新绑定单例中央的回调并恢复连接态。
    func onAppear() {
        wireCentral()
        if central.isConnected {
            phase = .connected
            statusText = "已连接"
        } else {
            statusText = "蓝牙可用，请扫描并连接设备"
        }
    }

    func refreshInfo() {
        device?.requestBattery()
        device?.requestVersion()
        device?.requestFileList()
    }

    func downloadAndTranscribe(file: CB08FileEntry) {
        guard let transcription else {
            statusText = "设备未连接"
            return
        }
        Task {
            statusText = "下载并转写中…"
            do {
                let transcript = try await transcription.downloadAndTranscribe(file: file, title: file.name)
                statusText = "已转写：\(transcript.fullText.count) 字"
            } catch {
                statusText = "失败：\(error.localizedDescription)"
            }
        }
    }

    func recordStart() { device?.recordStart() }
    func recordPause(paused: Bool) { device?.recordPause(paused: paused) }
    func recordSave() { device?.recordSave() }
    func realtimeStart() { device?.startRealtime() }
    func realtimeStop() { device?.stopRealtime() }

    private func wireCentral() {
        central.onDiscovered = { [weak self] peripheral in
            guard let self else { return }
            if !self.discovered.contains(where: { $0.identifier == peripheral.identifier }) {
                self.discovered.append(peripheral)
            }
            self.statusText = "发现 \(self.discovered.count) 台设备，点击连接"
        }
        central.onPoweredOn = { [weak self] powered in
            self?.statusText = powered ? "蓝牙可用，请扫描并连接设备" : "蓝牙不可用"
        }
        central.onAutoReconnect = { [weak self] in
            self?.phase = .connecting
            self?.statusText = "自动重连上次设备…"
        }
        central.onPeripheralConnected = { [weak self] in
            guard let self else { return }
            let device = CB08Device(transport: self.central, seqGenerator: { self.nextSeq() })
            self.device = device
            device.onBattery = { self.battery = $0 }
            device.onFileList = { self.files = $0 }
            let settings = AppSettings(storeDirectory: AppEnvironment.defaultStoreDirectory())
            self.transcription = DeviceTranscriptionService(
                device: device,
                engine: FileTranscriptionEngineFactory.make(settings: settings),
                store: self.store
            )
            self.phase = .connected
            self.statusText = "已连接，读取设备信息…"
            self.refreshInfo()
        }
        central.onPeripheralDisconnected = { [weak self] in
            self?.phase = .idle
            self?.statusText = "设备已断开"
        }
        central.onError = { [weak self] msg in
            self?.phase = .error(msg)
        }
    }

    private func nextSeq() -> UInt8 {
        defer { seq &+= 1 }
        return seq
    }
}
