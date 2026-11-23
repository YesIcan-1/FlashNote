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
    /// 当前协商的 ATT MTU 有效载荷长度（字节），分片写入依据。
    /// iOS 27 SDK 不暴露 BLE PHY 编程 API，PHY 由系统自动协商；MTU 是 App 侧可观测的传输能力信号。
    var maximumWriteLength: Int { get }
}

extension BLETransport {
    /// 默认实现：能力未知时按 20 字节（BLE 最小 MTU）处理，便于测试 mock 无需覆写。
    var maximumWriteLength: Int { 20 }
}
