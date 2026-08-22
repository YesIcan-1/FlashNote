import Foundation
import CoreBluetooth
import FlashNoteCore

/// 扫描/连接 QS668（Service 0xAE20），封装为 BLETransport。
/// CoreBluetooth 细节在此层；高层逻辑在 CB08Device（可测）。
final class CB08Central: NSObject, BLETransport {
    /// 蓝牙模块是否可用（poweredOn）。
    var onPoweredOn: ((Bool) -> Void)?
    /// 已连接外设 / 已断开。
    var onPeripheralConnected: (() -> Void)?
    var onPeripheralDisconnected: (() -> Void)?
    var onDiscovered: ((CBPeripheral) -> Void)?
    var onError: ((String) -> Void)?

    private var manager: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var writeChar: CBCharacteristic?
    private var notifyChar: CBCharacteristic?
    private var onNotify: ((Data) -> Void)?

    static let serviceUUID = CBUUID(string: "AE20")
    private static let writeUUID = CBUUID(string: "AE21")
    private static let notifyUUID = CBUUID(string: "AE22")

    override init() {
        super.init()
        manager = CBCentralManager(delegate: self, queue: .main)
    }

    func scan() {
        manager.scanForPeripherals(withServices: [Self.serviceUUID], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }

    func connect(_ peripheral: CBPeripheral) {
        self.peripheral = peripheral
        peripheral.delegate = self
        manager.stopScan()
        manager.connect(peripheral, options: nil)
    }

    func disconnect() {
        if let peripheral { manager.cancelPeripheralConnection(peripheral) }
    }

    // MARK: BLETransport
    func write(_ data: Data) {
        guard let peripheral, let writeChar else { return }
        peripheral.writeValue(data, for: writeChar, type: .withoutResponse)
    }

    func subscribe(onNotify: @escaping (Data) -> Void) {
        self.onNotify = onNotify
    }
}

extension CB08Central: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        onPoweredOn?(central.state == .poweredOn)
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        onDiscovered?(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([Self.serviceUUID])
        onPeripheralConnected?()
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        onError?("连接失败：\(error?.localizedDescription ?? "未知")")
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        onPeripheralDisconnected?()
    }
}

extension CB08Central: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let service = peripheral.services?.first(where: { $0.uuid == Self.serviceUUID }) else { return }
        peripheral.discoverCharacteristics([Self.writeUUID, Self.notifyUUID], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        writeChar = service.characteristics?.first(where: { $0.uuid == Self.writeUUID })
        if let notify = service.characteristics?.first(where: { $0.uuid == Self.notifyUUID }) {
            notifyChar = notify
            peripheral.setNotifyValue(true, for: notify)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == Self.notifyUUID, let value = characteristic.value else { return }
        onNotify?(value)
    }
}
