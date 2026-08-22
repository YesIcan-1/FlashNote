# FlashNote Phase A 实施计划（QS668 BLE 硬件集成）

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 FlashNote 通过 BLE 连接 QS668/CB08 AI 录音卡：读取设备信息、文件列表、**下载 WAV 转写**、实时 OPUS 流解码转写、远端录音控制，并提供设备面板 UI。

**Architecture:** 协议层（帧/CRC-16/XMODEM/SEQ，纯 Swift，放核心包可 `swift test`）；设备层（CoreBluetooth Central + `BLETransport` 抽象，逻辑可 mock 测试）；下载路径设备直接返回 WAV（无 OPUS 解码）；实时流是 40B OPUS 包 → 需独立解码组件；实时 ASR 可插拔（默认阿里云 Qwen-ASR-Realtime，Apple Speech 兜底）。

**Tech Stack:** CoreBluetooth、AVFoundation（AVAudioFile 读 WAV）、核心层 FlashNoteCore、Swift Testing、SwiftUI。

**环境约束（沿用）：** `xcodebuild` 带 `ONLY_ACTIVE_ARCH=YES ARCHS=arm64`；macOS 测试 target；iOS 用 `-sdk iphoneos CODE_SIGNING_ALLOWED=NO`；测试文件条件导入；真机验证用 `open` 启动。**BLE 测试需先在 macOS 蓝牙设置把录音笔配对**（本计划 Task 4 端到端真机验证）。

---

## 文件结构

```
FlashNoteCore/Sources/FlashNoteCore/Device/
├── CB08Protocol.swift            # 帧构造/流式解析/CRC-16/XMODEM/SEQ/命令常量/文件列表解码
├── CB08Command.swift             # TYPE/CMD 常量 + 参数编码
FlashNoteCore/Tests/FlashNoteCoreTests/
├── CB08ProtocolTests.swift
Services/Device/
├── BLETransport.swift            # CoreBluetooth 封装抽象（可 mock）
├── CB08Central.swift             # 扫描/连接（CoreBluetooth 实现）
└── CB08Device.swift              # 高层：设备信息/列表/下载/实时/录音控制（mock transport 可测）
Features/Device/
├── DevicePanelView.swift         # 设备面板（连接/电量/列表/下载/实时/录音控制）
├── DeviceViewModel.swift         # 设备状态机（可测）
Services/Audio/
└── OpusDecoder.swift             # 40B OPUS 包 → PCM（libopus/AudioToolbox，见 Task 4）
Tests/
├── CB08DeviceTests.swift
└── OpusDecoderTests.swift
```

---

### Task 1: 协议层（核心包，可测）

**Files:**
- Create: `FlashNoteCore/Sources/FlashNoteCore/Device/CB08Protocol.swift`
- Create: `FlashNoteCore/Sources/FlashNoteCore/Device/CB08Command.swift`
- Create: `FlashNoteCore/Tests/FlashNoteCoreTests/CB08ProtocolTests.swift`

- [ ] **Step 1: 写失败测试**

```swift
import Testing
import Foundation
@testable import FlashNoteCore

struct CB08ProtocolTests {
    @Test func crc16MatchesVector() {
        // 标准校验向量 "123456789" → 0x31C3（XMODEM）
        let crc = CB08Crc16.compute(
            bytes: Array("123456789".utf8),
            initial: 0x0000
        )
        #expect(crc == 0x31C3)
    }

    @Test func buildFrameMatchesVendorVector() {
        // 协议 7.3 真机成功帧：offset=0 + "note20260710-162938.wav"（24B填充）
        let params = CB08Command.importRequest(offset: 0, filename: "note20260710-162938.wav")
        let frame = CB08Frame.build(seq: 0x03, data: CB08Command.data(type: 2, cmd: 2, params: params))
        let hex = frame.map { String(format: "%02x", $0) }.joined()
        // 期望（从文中 7.3 帧，SEQ=03，LEN=30）：
        // 5a 03 9e 20 1e 00 02 02 00 00 00 00 6e 6f 74 65 32 30 32 36 30 37 31 30 2d 31 36 32 39 33 38 2e 77 61 76 00
        let expected = "5a039e201e000202000000006e6f746532303236303731302d3136323933382e77617600"
        #expect(hex == expected, "帧与真机抓包不一致: \(hex)")
    }

    @Test func streamParserReassemblesFragments() {
        var parser = CB08FrameParser()
        // 一帧被切两半 + 噪声
        let frame = CB08Frame.build(seq: 1, data: CB08Command.data(type: 0, cmd: 3, params: []))
        var frames: [CB08Frame] = []
        frames += parser.feed(Data([0x5A, 0x01]))      // 半帧
        frames += parser.feed(Data([0x00, 0x00, 0x00])) // 补 CRC/LEN 前段
        frames += parser.feed(Data(frame.suffix(10)))   // 补后段
        #expect(frames.count == 1)
        #expect(frames[0].type == 0)
        #expect(frames[0].cmd == 3)
    }

    @Test func decodeFileList() {
        // count:4B BE + N×28B(date:4B BE + size:4B BE + name:20B)
        var body = Data()
        body.append(Data([0, 0, 0, 1])) // count = 1 (BE)
        body.append(Data([0, 0, 0, 5])) // time = 5s (BE)
        body.append(Data([0, 0, 0, 100])) // size = 100 (BE)
        var name = Array("note20260710-162938".utf8)
        name.append(contentsOf: Array(repeating: 0, count: 20 - name.count))
        body.append(Data(name))
        let entries = CB08FileList.decode(body)
        #expect(entries.count == 1)
        #expect(entries[0].size == 100)
        #expect(entries[0].name.hasPrefix("note20260710"))
        #expect(entries[0].candidateNames == ["note20260710-162938.wav", "note20260710-162938.opus"])
    }
}
```

- [ ] **Step 2: 运行确认失败**

```bash
cd FlashNoteCore && swift test
```
Expected: 编译失败——找不到 `CB08Crc16` / `CB08Frame` / `CB08FrameParser` / `CB08FileList`。

- [ ] **Step 3: 实现**

`CB08Command.swift`:

```swift
import Foundation

/// CB08 命令常量与参数编码。
public enum CB08Command {
    // TYPE
    public static let typeControl: UInt8 = 0
    public static let typeRealtime: UInt8 = 1
    public static let typeFile: UInt8 = 2
    public static let typeKey: UInt8 = 3

    public static func data(type: UInt8, cmd: UInt8, params: Data = Data()) -> Data {
        var d = Data([type, cmd])
        d.append(params)
        return d
    }

    /// 文件下载请求 2-2：offset(4B LE) + filename(24B NUL填充)。
    public static func importRequest(offset: UInt32, filename: String) -> Data {
        var params = Data()
        params.append(UInt32(offset).littleEndianBytes)
        var name = Array(filename.utf8.prefix(24))
        name.append(contentsOf: Array(repeating: 0, count: 24 - name.count))
        params.append(contentsOf: name)
        return params
    }
}

extension UInt32 {
    var littleEndianBytes: Data {
        var v = littleEndian
        return Data(bytes: &v, count: 4)
    }
}
```

`CB08Protocol.swift`:

```swift
import Foundation

/// CRC-16/XMODEM：多项式 0x1021，初值 0，RefIn/RefOut=false，XorOut=0。
public enum CB08Crc16 {
    public static func compute(bytes: [UInt8], initial: UInt16 = 0x0000) -> UInt16 {
        var crc = initial
        for b in bytes {
            crc ^= UInt16(b) << 8
            for _ in 0..<8 {
                crc = (crc & 0x8000) != 0 ? (crc << 1) ^ 0x1021 : (crc << 1)
            }
        }
        return crc
    }
}

public struct CB08Frame: Equatable {
    public let seq: UInt8
    public let data: Data
    public var type: UInt8 { data.count >= 1 ? data[data.startIndex] : 0 }
    public var cmd: UInt8? { data.count >= 2 ? data[data.startIndex + 1] : nil }
    public var params: Data { data.count > 2 ? data.dropFirst(2) : Data() }

    /// 构造完整帧：MAGIC + SEQ + CRC(LE) + LEN(LE) + DATA。
    public static func build(seq: UInt8, data: Data) -> Data {
        var frame = [0x5A, seq & 0xFF]
        let len = UInt16(data.count)
        let lenBytes = [UInt8(len & 0xFF), UInt8((len >> 8) & 0xFF)]
        var crcInput = lenBytes + Array(data)
        let crc = CB08Crc16.compute(bytes: crcInput)
        frame.append(contentsOf: [UInt8(crc & 0xFF), UInt8((crc >> 8) & 0xFF)])
        frame.append(contentsOf: lenBytes)
        frame.append(contentsOf: data)
        return Data(frame)
    }
}

/// 流式帧解析器：支持半帧/多帧/噪声重同步、独立缓冲区（AE22/AE23 各一个）。
public struct CB08FrameParser {
    private var buffer = Data()

    public init() {}

    public mutating func feed(_ chunk: Data) -> [CB08Frame] {
        buffer.append(chunk)
        var frames: [CB08Frame] = []
        while true {
            guard let frame = _tryParseOne() else { break }
            frames.append(frame)
        }
        return frames
    }

    private mutating func _tryParseOne() -> CB08Frame? {
        // 丢弃 MAGIC 前噪声
        while !buffer.isEmpty && buffer[buffer.startIndex] != 0x5A {
            buffer.removeFirst()
        }
        guard buffer.count >= 6 else { return nil }
        let len = Int(buffer[buffer.startIndex + 4]) | (Int(buffer[buffer.startIndex + 5]) << 8)
        if len > 8192 {
            // 假帧头，跳一字节重同步
            buffer.removeFirst()
            return nil
        }
        guard buffer.count >= 6 + len else { return nil }
        let data = buffer.subdata(in: (buffer.startIndex + 6)..<(buffer.startIndex + 6 + len))
        let lenBytes = [UInt8(buffer[buffer.startIndex + 4]), UInt8(buffer[buffer.startIndex + 5])]
        let expectedCRC = UInt16(buffer[buffer.startIndex + 2]) | (UInt16(buffer[buffer.startIndex + 3]) << 8)
        let actualCRC = CB08Crc16.compute(bytes: lenBytes + Array(data))
        let seq = buffer[buffer.startIndex + 1]
        buffer.removeFirst(6 + len)
        if actualCRC != expectedCRC { return nil } // CRC 错，丢弃
        return CB08Frame(seq: seq, data: data)
    }
}

/// 文件列表条目。
public struct CB08FileEntry: Equatable {
    public let time: UInt32
    public let size: UInt32
    public let name: String

    public var candidateNames: [String] {
        // 优先 base.wav，其次 base.opus，最后原始截断名
        let base = name.replacingOccurrences(of: ".", with: ".") // 列表名常截断扩展名
        var names: [String] = []
        for ext in [".wav", ".opus"] {
            if !name.hasSuffix(ext) {
                let trimmed = name.replacingOccurrences(of: "\u{0000}", with: "")
                names.append(trimmed + ext)
            }
        }
        names.append(name.replacingOccurrences(of: "\u{0000}", with: ""))
        return names
    }
}

/// 文件列表解码（count:4B BE + N×28B 条目）。
public enum CB08FileList {
    public static func decode(_ body: Data) -> [CB08FileEntry] {
        guard body.count >= 4 else { return [] }
        let count = Int(readBE(body, 0, 4))
        var entries: [CB08FileEntry] = []
        var offset = 4
        for _ in 0..<count {
            guard offset + 28 <= body.count else { break }
            let time = UInt32(readBE(body, offset, 4))
            let size = UInt32(readBE(body, offset + 4, 4))
            let nameRaw = body.subdata(in: (offset + 8)..<(offset + 28))
            let name = String(data: nameRaw, encoding: .utf8)?
                .replacingOccurrences(of: "\u{0000}", with: "") ?? ""
            entries.append(CB08FileEntry(time: time, size: size, name: name))
            offset += 28
        }
        return entries
    }

    private static func readBE(_ data: Data, _ offset: Int, _ count: Int) -> UInt64 {
        var v: UInt64 = 0
        for i in 0..<count {
            v = (v << 8) | UInt64(data[data.startIndex + offset + i])
        }
        return v
    }
}
```

注意：帧构建的 CRC 计算输入 = LEN 原始 2 字节 + DATA（不含 MAGIC/SEQ/CRC）。上述 `build` 满足。测试 Step 1 的第 2 个用例依赖 CRC 和帧完全匹配真机抓包——若 CRC/字节序有一处不对会失败，需修正实现。

- [ ] **Step 4: 运行确认通过**

```bash
cd FlashNoteCore && swift test
```
Expected: 核心测试全部通过（含新增 CB08ProtocolTests）。

- [ ] **Step 5: 提交**

```bash
cd .. && git add FlashNoteCore && git commit -m "feat: add CB08 BLE protocol layer (frame/CRC/parser/file list)"
```

---

### Task 2: 设备层（BLETransport 抽象 + 高层逻辑）

**Files:**
- Create: `Services/Device/BLETransport.swift`
- Create: `Services/Device/CB08Central.swift`
- Create: `Services/Device/CB08Device.swift`
- Create: `Tests/CB08DeviceTests.swift`

- [ ] **Step 1: 写失败测试**（用 MockTransport 测设备逻辑）

```swift
import Testing
import Foundation
import FlashNoteCore
#if os(macOS)
@testable import FlashNoteMac
#else
@testable import FlashNote
#endif

/// 测试替身：内存 BLE 传输，记录写入、可回放通知。
final class MockBLETransport: BLETransport {
    var wrote: [Data] = []
    var onNotify: ((Data) -> Void)?
    func write(_ data: Data) { wrote.append(data) }
    func subscribe(onNotify: @escaping (Data) -> Void) { self.onNotify = onNotify }
}

struct CB08DeviceTests {
    @Test func buildConnectAndBatteryFrame() throws {
        let transport = MockBLETransport()
        let device = CB08Device(transport: transport, seqGenerator: { _ in 0 })
        device.connect()
        // 首个命令是同步时间？实际连接后 send(type:0, cmd:3) 请求电量（示例）
        device.requestBattery()
        #expect(transport.wrote.count == 2)
        let frame = CB08FrameParserTool.parse(transport.wrote[1])
        #expect(frame.type == 0)
        #expect(frame.cmd == 3)
    }

    @Test func handleBatteryResponse() throws {
        let transport = MockBLETransport()
        let device = CB08Device(transport: transport, seqGenerator: { _ in 0 })
        var battery: Int?
        device.onBattery = { battery = $0 }
        // TYPE=0 CMD=4 电量应答，值 90
        transport.onNotify?(CB08Frame.build(seq: 0, data: CB08Command.data(type: 0, cmd: 4, params: Data([90]))))
        #expect(battery == 90)
    }

    @Test func fileListAccumulatesAcrossFrames() throws {
        let transport = MockBLETransport()
        let device = CB08Device(transport: transport, seqGenerator: { _ in 0 })
        var entries: [CB08FileEntry] = []
        device.onFileList = { entries = $0 }
        // 两个列表帧
        transport.onNotify?(CB08Frame.build(seq: 0, data: CB08Command.data(type: 2, cmd: 1, params: entryBody(1))))
        transport.onNotify?(CB08Frame.build(seq: 0, data: CB08Command.data(type: 2, cmd: 1, params: entryBody(1))))
        transport.onNotify?(CB08Frame.build(seq: 0, data: CB08Command.data(type: 2, cmd: 18, params: Data([0]))))
        #expect(entries.count == 2)
    }

    private func entryBody(_ n: Int) -> Data {
        var d = Data()
        d.append(contentsOf: [0,0,0,1]) // count=1
        d.append(contentsOf: [0,0,0,5]) // time
        d.append(contentsOf: [0,0,0,UInt8(n*100)]) // size
        var name = Array("note\(n)".utf8)
        name.append(contentsOf: Array(repeating: 0, count: 20-name.count))
        d.append(contentsOf: name)
        return d
    }
}
```

- [ ] **Step 2: 运行确认失败**

- [ ] **Step 3: 实现**

`BLETransport.swift`:

```swift
import Foundation

/// BLE 传输抽象（CoreBluetooth 实现 / 测试用 mock）。
protocol BLETransport: AnyObject {
    func write(_ data: Data)
    func subscribe(onNotify: @escaping (Data) -> Void)
}
```

`CB08Central.swift`（CoreBluetooth 实现）：

```swift
import Foundation
import CoreBluetooth
import Combine

/// 扫描/连接 QS668（服务 0xAE20），封装为 BLETransport。
final class CB08Central: NSObject, BLETransport, CBCentralManagerDelegate, CBPeripheralDelegate {
    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var writeChar: CBCharacteristic?
    private var onNotify: ((Data) -> Void)?
    private var parser = CB08FrameParser()

    var onConnected: ((Bool) -> Void)?
    var onDiscovered: ((String) -> Void)?
    var onBattery/onFileList/...  // 透传到设备层

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    func scan() {
        central.scanForPeripherals(withServices: [CBUUID(string: "AE20")], options: nil)
    }
    // ... 连接/订阅/写入，见 Step 3 完整实现（CoreBluetooth 细节）
}
```

（CB08Central 因 CoreBluetooth 无法单测，逻辑薄，只做传输；高层逻辑在 CB08Device 用 Mock transport 测试。）

`CB08Device.swift`（高层，可测）：

```swift
import Foundation
import FlashNoteCore

/// 设备高层逻辑：请求应答匹配、文件列表组装、命令构造。
final class CB08Device {
    private let transport: BLETransport
    private let seqGenerator: () -> UInt8
    private var fileBuffer: [CB08FileEntry] = []
    var ongoingFrame: CB08Frame?  // 下载会话等

    var onBattery: ((Int) -> Void)?
    var onFileList: (([CB08FileEntry]) -> Void)?
    var onRealtimeAudio: ((Data) -> Void)?
    var onRealtimeState: ((UInt8) -> Void)?
    var onRecordState: ((UInt8) -> Void)?

    init(transport: BLETransport, seqGenerator: @escaping () -> UInt8) {
        self.transport = transport
        self.seqGenerator = seqGenerator
        transport.subscribe { [weak self] data in
            self?.handleNotification(data)
        }
    }

    func send(type: UInt8, cmd: UInt8, params: Data = Data()) {
        let frame = CB08Frame.build(seq: seqGenerator(), data: CB08Command.data(type: type, cmd: cmd, params: params))
        transport.write(frame)
    }

    func requestBattery() { send(type: 0, cmd: 3) }
    func requestFileList() { fileBuffer = []; send(type: 2, cmd: 0) }
    func requestImport(filename: String, offset: UInt32 = 0) {
        send(type: 2, cmd: 2, params: CB08Command.importRequest(offset: offset, filename: filename))
    }
    func startRealtime() { send(type: 1, cmd: 0) }
    func stopRealtime() { send(type: 1, cmd: 2) }
    func recordPause(paused: Bool) { send(type: 1, cmd: 3, params: Data([paused ? 1 : 0])) }
    func recordStart() { send(type: 3, cmd: 1) }
    func recordSave() { send(type: 3, cmd: 3) }

    private func handleNotification(_ data: Data) {
        var parser = CB08FrameParser()
        let frames = parser.feed(data)
        for frame in frames {
            switch frame.type {
            case 0:
                if frame.cmd == 4, let p = frame.params.first { onBattery?(Int(p)) }
            case 1:
                if frame.cmd == 1 { onRealtimeAudio?(frame.params) }
                else if frame.cmd == 4 { frame.params.first.map { onRealtimeState?($0) } }
            case 2:
                if frame.cmd == 1 {
                    fileBuffer += CB08FileList.decode(frame.params)
                } else if frame.cmd == 18 {
                    onFileList?(fileBuffer); fileBuffer = []
                }
            case 3:
                if frame.cmd == 20 { frame.params.first.map { onRecordState?($0) } }
            default: break
            }
        }
    }
}
```

注意：`CB08FrameParser` 在核心包为 `public`，设备层实例化一个新的 parser（每次 notify 调 feed 会丢跨包半帧——应保留 parser 实例，见 Step 3 修正：`CB08Device` 持有私有 parser）。

- [ ] **Step 4: 运行确认通过**（含修正 parser 实例化）

- [ ] **Step 5: 提交**

```bash
git add Services Tests && git commit -m "feat: add CB08 device layer (transport abstraction + high-level logic)"
```

---

### Task 3: 下载 WAV 并转写（打通设备文件 → 转写）

**Files:**
- Modify: `Services/Device/CB08Device.swift`（下载会话）
- Create: `Services/Device/DeviceTranscriptionService.swift`（下载 → WAV → 转写 → 保存）

- [ ] **Step 1: 实现下载会话**（CB08Device 内：请求导入 → 接收 2-4 数据分片 → 2-5 结束，候选名回退，写 .wav）
- [ ] **Step 2: 实现转写编排**`DeviceTranscriptionService`：`downloadAndTranscribe(file:) async throws -> Transcript`
- [ ] **Step 3: 测试**（mock transport 模拟下载帧） + 双平台构建

- [ ] **Step 4: 提交**

```bash
git add Services && git commit -m "feat: device file download to WAV and transcription"
```

---

### Task 4: 实时 OPUS 流解码

**Files:**
- Create: `Services/Audio/OpusDecoder.swift`
- Create: `Tests/OpusDecoderTests.swift`

- [ ] **Step 1: 调研 + 选定 OPUS 解码方式**

设备实时流是 40B/包原始 OPUS（Opus config 9，20ms，16kHz）。Apple 原生无 OGG/Opus 解码。方案（三选一，按可从 GitHub 拉取优先级）：
   a. SwiftPM C 目标打包 libopus（`opus` + 桥接头）——最稳，但需网络拉取。
   b. AudioToolbox `AudioConverter`（若支持该格式——需验证）。
   c. 参照厂商脚本：40B 包 → 包装 OggS → 用 `AVAudioFile`/`AudioFile` 读（若支持）。

先在项目里验证可行的解码路径；若 libopus 不可拉取，c 方案包装 Ogg + 系统解码。

- [ ] **Step 2: 实现 OpusDecoder** + 帧切片（40B 对齐）
- [ ] **Step 3: 测试对流式**（录一段已知 OPUS 喂 decoder 验 PCM 长度）+ 双平台构建
- [ ] **Step 4: 提交**

```bash
git add Services && git commit -m "feat: OpusDecoder for realtime stream"
```

---

### Task 5: 设备面板 UI + 实时转写接入

**Files:**
- Create: `Features/Device/DeviceViewModel.swift`
- Create: `Features/Device/DevicePanelView.swift`
- Modify: `App/RootView.swift`（设备入口）

- [ ] **Step 1-5: 设备面板 UI**（连接/电量/文件列表/下载进度/实时转写/录音控制/增益），实时转写默认走 `AlibabaQwenASR`（用户设 AppKey，见 M3 设置），Apple Speech 兜底
- [ ] **Step 6: 构建 + 提交**

---

### Task 6: 端到端真机验证

- [ ] **Step 1-5: 真机清单**（蓝牙配对 QS668 后）：连接 → 电量 → 列表 → 下载 WAV → 转写 → 实时流 → 录音控制
- [ ] **Step 6: 更新 README + 合并**

---

## 自检结果

**Spec 覆盖（设计 V2 §2/§5.1-5.4）：** 协议层 → Task 1；设备层 → Task 2；下载+转写 → Task 3；实时 OPUS → Task 4；设备面板/实时转写 → Task 5；真机 → Task 6。

**类型一致性：** `CB08Frame/FrameParser/Crc16/FileEntry/Command` 在核心包 public，供 app 与核心测试复用；`BLETransport` 协议在 app 层，mock 与 CoreBluetooth 实现共用；`onBattery/onFileList/onRealtimeAudio` 等回调在设备层。

**风险与取舍：**
- Task 4 OPUS 解码是最大不确定性（Apple 无原生 OGG/Opus 解码；需 libopus 或系统路径）。若不可行，实时流退回"设备端转 WAV 后下载"或"录音控制后下载 WAV 转写"（放弃实时，改用准实时）。
- 真机验证需先蓝牙配对（Task 6）。
- 实时转写默认阿里云 Qwen-ASR（用户填 AppKey）；Apple Speech 兜底；具体 ASR 接入细节在 M3 设置页完善，本计划先打通管线（OPUS→PCM→可插拔 ASR）。
