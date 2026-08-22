import Foundation
import SwiftUI
import FlashNoteCore

/// 全局依赖装配：存储 + 设置。App 层通过 Environment 注入。
@Observable
final class AppEnvironment {
    let store: RecordingStore
    /// 应用级设备会话：页面切换不应重建蓝牙状态与传输回调。
    let deviceSession: DeviceViewModel

    init(store: RecordingStore) {
        self.store = store
        self.deviceSession = DeviceViewModel(store: store)
    }

    /// 生产装配：文件存储落在 Application Support/FlashNote。
    static func makeLive() -> AppEnvironment {
        let store = try! FileRecordingStore(root: Self.defaultStoreDirectory())
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
