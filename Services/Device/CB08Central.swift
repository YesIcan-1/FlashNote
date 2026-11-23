import Foundation
import os
import CoreBluetooth
import FlashNoteCore

let deviceLogger = Logger(subsystem: "com.flashnote.mac", category: "device")

/// 扫描/连接 QS668（Service 0xAE20），封装为 BLETransport。
/// 单例：连接状态在 tab 切换/视图重建后保持。
final class CB08Central: NSObject, BLETransport {
    static let shared = CB08Central()

    var onPoweredOn: ((Bool) -> Void)?
    var onPeripheralConnected: (() -> Void)?
    var onPeripheralDisconnected: (() -> Void)?
    var onDiscovered: ((CBPeripheral) -> Void)?
    var onError: ((String) -> Void)?
    /// 自动重连已记住的设备。
    var onAutoReconnect: (() -> Void)?

    private static let rememberedKey = "rememberedDeviceID"
    private(set) var isAutoReconnecting = false
    private var shouldReconnect = false

    private(set) var isConnected = false

    /// 当前协商的 ATT MTU 有效载荷长度（分片写入依据）。iOS 默认协商 185B。
    /// 注：iOS 27 SDK 已不暴露 BLE PHY 编程 API，2M PHY 由系统自动协商，
    /// App 侧可观测/可控的传输能力信号即此 MTU 长度。
    private(set) var maximumWriteLength: Int = 185

    private var manager: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var writeChar: CBCharacteristic?
    private var notifyChar: CBCharacteristic?
    private var eventChar: CBCharacteristic?
    private var onControlNotify: ((Data) -> Void)?
    private var onEventNotify: ((Data) -> Void)?
    private var controlNotificationCount = 0
    private var controlNotificationBytes = 0
    private var controlDispatchNanoseconds: UInt64 = 0
    private var lastControlNotificationNanoseconds: UInt64?
    private var controlGapBuckets = [Int](repeating: 0, count: 7)
    private let controlGapLimits: [UInt64] = [1_000_000, 5_000_000, 10_000_000, 20_000_000, 40_000_000, 80_000_000]

    static let serviceUUID = CBUUID(string: "AE20")
    private static let writeUUID = CBUUID(string: "AE21")
    private static let notifyUUID = CBUUID(string: "AE22")
    private static let eventUUID = CBUUID(string: "AE23")

    private override init() {
        super.init()
        manager = CBCentralManager(delegate: self, queue: .main)
    }

    @discardableResult
    func scan() -> Bool {
        guard manager.state == .poweredOn else { return false }
        manager.scanForPeripherals(withServices: [Self.serviceUUID], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        return true
    }

    func stopScan() { manager.stopScan() }

    func connect(_ peripheral: CBPeripheral) {
        shouldReconnect = true
        self.peripheral = peripheral
        peripheral.delegate = self
        manager.stopScan()
        UserDefaults.standard.set(peripheral.identifier.uuidString, forKey: Self.rememberedKey)
        manager.connect(peripheral, options: nil)
    }

    func clearRememberedDevice() {
        UserDefaults.standard.removeObject(forKey: Self.rememberedKey)
    }

    private func rememberedDeviceID() -> UUID? {
        guard let s = UserDefaults.standard.string(forKey: Self.rememberedKey) else { return nil }
        return UUID(uuidString: s)
    }

    func disconnect() {
        shouldReconnect = false
        isAutoReconnecting = false
        isConnected = false
        if let peripheral { manager.cancelPeripheralConnection(peripheral) }
        writeChar = nil
        notifyChar = nil
        eventChar = nil
    }

    func recoverUnresponsiveConnection() {
        guard let peripheral, isConnected else { return }
        shouldReconnect = true
        manager.cancelPeripheralConnection(peripheral)
    }

    // MARK: BLETransport
    func write(_ data: Data) {
        guard let peripheral, let writeChar else { return }

        let chunk = max(20, peripheral.maximumWriteValueLength(for: .withoutResponse))
        maximumWriteLength = chunk
        guard data.count > chunk else {
            peripheral.writeValue(data, for: writeChar, type: .withoutResponse)
            return
        }
        // 帧超出 MTU 时按有效载荷长度分片连续无应答写入（防御大帧；协议层帧一般小于 MTU）。
        var offset = 0
        while offset < data.count {
            let end = min(offset + chunk, data.count)
            peripheral.writeValue(data.subdata(in: offset..<end), for: writeChar, type: .withoutResponse)
            offset = end
        }
    }

    func subscribe(
        onControlNotify: @escaping (Data) -> Void,
        onEventNotify: @escaping (Data) -> Void
    ) {
        self.onControlNotify = onControlNotify
        self.onEventNotify = onEventNotify
    }
}

extension CB08Central: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        onPoweredOn?(central.state == .poweredOn)
        // 蓝牙就绪且记住了设备 → 自动重连（无需重新扫描）
        guard central.state == .poweredOn, !isConnected, let id = rememberedDeviceID() else { return }
        let peripherals = central.retrievePeripherals(withIdentifiers: [id])
        if let peripheral = peripherals.first {
            isAutoReconnecting = true
            connect(peripheral)
            onAutoReconnect?()
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        onDiscovered?(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        isAutoReconnecting = false
        peripheral.discoverServices([Self.serviceUUID])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        if shouldReconnect { scheduleReconnect(peripheral) }
        else { onError?("连接失败：\(error?.localizedDescription ?? "未知")") }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        isConnected = false
        onPeripheralDisconnected?()
        if shouldReconnect { scheduleReconnect(peripheral) }
    }

    private func scheduleReconnect(_ peripheral: CBPeripheral) {
        isAutoReconnecting = true
        onAutoReconnect?()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self, self.shouldReconnect, self.manager.state == .poweredOn else { return }
            self.manager.connect(peripheral, options: nil)
        }
    }
}

extension CB08Central: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let service = peripheral.services?.first(where: { $0.uuid == Self.serviceUUID }) else { return }
        peripheral.discoverCharacteristics([Self.writeUUID, Self.notifyUUID, Self.eventUUID], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        writeChar = service.characteristics?.first(where: { $0.uuid == Self.writeUUID })
        notifyChar = service.characteristics?.first(where: { $0.uuid == Self.notifyUUID })
        eventChar = service.characteristics?.first(where: { $0.uuid == Self.eventUUID })
        if let notifyChar { peripheral.setNotifyValue(true, for: notifyChar) }
        if let eventChar { peripheral.setNotifyValue(true, for: eventChar) }
        if writeChar == nil || notifyChar == nil || eventChar == nil {
            onError?("设备缺少必要的 BLE 特征")
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            onError?("订阅设备通知失败：\(error.localizedDescription)")
            return
        }
        guard writeChar != nil,
              notifyChar?.isNotifying == true,
              eventChar?.isNotifying == true,
              !isConnected else { return }
        isConnected = true
        // 连接就绪后刷新协商 MTU（PHY 由系统自动管理，无编程 API）。
        maximumWriteLength = max(20, peripheral.maximumWriteValueLength(for: .withoutResponse))
        controlNotificationCount = 0
        controlNotificationBytes = 0
        controlDispatchNanoseconds = 0
        lastControlNotificationNanoseconds = nil
        controlGapBuckets = [Int](repeating: 0, count: 7)
        deviceLogger.info("BLE connected negotiatedWriteLength=\(self.maximumWriteLength, privacy: .public)")
        onPeripheralConnected?()
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let value = characteristic.value else { return }
        switch characteristic.uuid {
        case Self.notifyUUID:
            let started = DispatchTime.now().uptimeNanoseconds
            if let lastControlNotificationNanoseconds {
                let gap = started - lastControlNotificationNanoseconds
                let bucket = controlGapLimits.firstIndex(where: { gap < $0 }) ?? 6
                controlGapBuckets[bucket] += 1
            }
            lastControlNotificationNanoseconds = started
            onControlNotify?(value)
            controlNotificationCount += 1
            controlNotificationBytes += value.count
            controlDispatchNanoseconds += DispatchTime.now().uptimeNanoseconds - started
            if controlNotificationCount.isMultiple(of: 1_000) {
                let dispatchMilliseconds = Double(controlDispatchNanoseconds) / 1_000_000
                deviceLogger.info("AE22 notifications=\(self.controlNotificationCount, privacy: .public) rawBytes=\(self.controlNotificationBytes, privacy: .public) dispatch=\(dispatchMilliseconds, privacy: .public)ms gaps=<1/<5/<10/<20/<40/<80/>=80ms \(String(describing: self.controlGapBuckets), privacy: .public)")
            }
        case Self.eventUUID:
            onEventNotify?(value)
        default:
            break
        }
    }
}
