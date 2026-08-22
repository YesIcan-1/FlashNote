import Foundation

/// BLE 传输抽象（CoreBluetooth 实现 / 测试用 mock）。
protocol BLETransport: AnyObject {
    func write(_ data: Data)
    /// AE22 carries control/file/audio frames; AE23 carries physical-key and recording-state frames.
    /// They must remain separate because CoreBluetooth may fragment either characteristic independently.
    func subscribe(
        onControlNotify: @escaping (Data) -> Void,
        onEventNotify: @escaping (Data) -> Void
    )
}
