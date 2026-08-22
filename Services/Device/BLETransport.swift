import Foundation

/// BLE 传输抽象（CoreBluetooth 实现 / 测试用 mock）。
protocol BLETransport: AnyObject {
    func write(_ data: Data)
    func subscribe(onNotify: @escaping (Data) -> Void)
}
