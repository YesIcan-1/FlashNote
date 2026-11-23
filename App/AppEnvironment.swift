import Foundation
import SwiftUI
import FlashNoteCore

/// 全局依赖装配：存储 + 设置。App 层通过 Environment 注入。
@Observable
final class AppEnvironment {
    let store: RecordingStore
    let processing: RecordingProcessingCoordinator
    /// 应用级设备会话：页面切换不应重建蓝牙状态与传输回调。
    private(set) var deviceSession: DeviceViewModel?
    #if os(macOS)
    /// macOS 录音卡 USB 卷自动同步引擎（插卡即入库）。
    private(set) var usbSyncEngine: USBVolumeSyncEngine?
    #endif

    init(store: RecordingStore) {
        self.store = store
        self.processing = RecordingProcessingCoordinator(store: store, notify: { notice in
            AppNotificationService.shared.post(notice)
        })
    }

    func startDeviceSession() -> DeviceViewModel {
        if let deviceSession { return deviceSession }
        let session = DeviceViewModel(store: store, processing: processing)
        deviceSession = session
        return session
    }

    #if os(macOS)
    /// 启动（或复用）USB 卷自动同步：挂载监听 + 立即扫描已连接卷。幂等，可重复调用。
    func startUSBSync() {
        guard usbSyncEngine == nil else { return }
        let engine = USBVolumeSyncEngine(
            store: store,
            storeDirectory: Self.defaultStoreDirectory(),
            transcriptionFactory: {
                FileTranscriptionEngineFactory.make(settings: AppSettings(storeDirectory: Self.defaultStoreDirectory()))
            },
            processing: processing
        )
        engine.startMonitoring()
        usbSyncEngine = engine
    }
    #endif

    /// 生产装配：文件存储落在 Application Support/FlashNote。
    static func makeLive() -> AppEnvironment {
        let store = try! FileRecordingStore(root: Self.defaultStoreDirectory())
        try? RecordingTitle.backfillHardwareTitles(in: store)
        return AppEnvironment(store: store)
    }

    /// 默认数据目录：~/Library/Application Support/FlashNote
    static func defaultStoreDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("FlashNote", isDirectory: true)
    }
}

private struct AppEnvironmentKey: EnvironmentKey {
    static let defaultValue: AppEnvironment? = nil
}

extension EnvironmentValues {
    var appEnvironment: AppEnvironment? {
        get { self[AppEnvironmentKey.self] }
        set { self[AppEnvironmentKey.self] = newValue }
    }
}
