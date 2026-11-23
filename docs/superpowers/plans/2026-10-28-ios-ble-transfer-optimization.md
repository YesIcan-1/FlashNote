# FlashNote 传输优化实施计划：iOS BLE 提速 + macOS USB 卷自动同步

**日期：** 2026-10-28
**状态：** 实施中
**前置：** `2026-10-28-flashnote-qwennote-redesign.md` §5.2 / §10（双通道传输架构）
**目标平台：** iOS 17+ 先行（BLE 优化）、macOS 14+（USB 自动同步）

---

## 0. 背景与结论

实机确认 QS668/CB08 为**双通道**设备：USB 大容量存储（U 盘模式，`record/noteYYYYMMDD-HHMMSS.wav/.opus`）+ BLE（GATT 0xAE20）。无 Wi-Fi 模块。

- **macOS 主通道**：USB 直读（约 30MB/s，秒级）→ 本轮实现**卷挂载自动同步**。
- **iOS 无线通道**：BLE，物理天花板 50–200KB/s → 本轮实现**MTU 分片 + 2M PHY 探测 + 能力上报**，把 35min 录音（OPUS 4.2MB）下载从 9–35 分钟压到 20–90 秒。

## 1. iOS BLE 传输优化（CB08Central / BLETransport）

### 1.1 现状与目标

现状：`CB08Central.write` 一次写入整帧（依赖 iOS 默认 185B MTU，帧 > MTU 时静默失败风险）；无 MTU 能力上报。

目标：
| 项 | 现状 | 目标 |
|---|---|---|
| 帧写入 | 整帧单写 | 按 `maximumWriteValueLength` 分片，防御帧 > MTU |
| 能力可见 | 无 | `maximumWriteLength` 暴露给 UI/日志 |
| PHY | 系统自动协商 | 无需编程控制（见下） |

**SDK 现实（已实机确认）**：Xcode 27.0 / iOS 27.0 SDK 的 CoreBluetooth 头文件**已移除 BLE 5 PHY 编程 API**（`setPreferredPhy`/`phy`/`CBPhy2M` 均不存在，tbd 仅导出 `CBPhyStatsConfig*`）。2M PHY 由系统在连接条件允许时自动协商，App 侧可观测、可编程的传输能力信号为 ATT MTU（`maximumWriteValueLength`）。故本轮 PHY 不做代码级请求/探测。

### 1.2 改动清单

**`Services/Device/BLETransport.swift`**（协议扩展）
```swift
protocol BLETransport: AnyObject {
    func write(_ data: Data)
    func subscribe(onControlNotify: @escaping (Data) -> Void,
                   onEventNotify: @escaping (Data) -> Void)
    /// 当前协商的 ATT MTU 有效载荷长度（分片写入依据）
    var maximumWriteLength: Int { get }
}
// extension 提供默认值 20，测试 mock 无需覆写
```

**`Services/Device/CB08Central.swift`**
1. `maximumWriteLength`（默认 185）存储属性；
2. `write(_:)` 分片：`chunk = max(20, peripheral.maximumWriteValueLength(for: .withoutResponse))`，`data.count > chunk` 时按 chunk 切分连续无应答写入；
3. 连接就绪（三特征订阅完成）时刷新 `maximumWriteLength`。

**`Tests/CB08DeviceTests.swift`**：`MockBLETransport` 补齐协议新成员（默认值 185 / nil / no-op）。

### 1.3 下载流程（DeviceTranscriptionService，保持不动）

已有能力全部保留：断点续传（offset=partial 大小）、候选名回退（`.wav→.opus→raw`，仅 code=1 且 0 字节）、12s 空闲超时、流式写盘不驻留内存、`onDownloadData/onDownloadFinished/onDownloadCode`。分片/PHY 优化发生在传输层，对上层透明。

### 1.4 验收（iOS 真机）

1. 连接后 `maximumWriteLength` 反映实际协商值（≥ 185B 表示 iOS 默认大 MTU 生效）。
2. 下载 35min 录音（OPUS 4.2MB）：时间 ≤ 90s（185B MTU + 系统自动 PHY 优化后，实测基线 ~20–90s）。
3. 下载中断后重试从偏移量续传，不重复已收数据。

## 2. macOS USB 卷自动同步（USBVolumeSyncEngine）

### 2.1 行为定义

- 监听 `NSWorkspace.didMountNotification` / `didUnmountNotification`；
- 识别设备卷：挂载点下存在 `record/` 目录的 FAT 卷（卷名任意，如 `NO NAME`）；
- 扫描 `record/` 下 `noteYYYYMMDD-HHMMSS.wav`（`.opus` 成对存在，优先 WAV）；
- 增量去重：`UserDefaults` 持久化已导入设备文件名集合（键 `USBImportedFilenames`）；
- 导入：复制 WAV → 本地 `audio/{uuid}.wav` → 登记 `Recording`（title=设备文件名，createdAt=文件名时间戳，status=.recording）→ 自动转写（注入 `FileTranscriptionEngine`，复用 `RecordingTranscriptionService`）→ `markTranscribed`；
- 转写失败不阻塞导入：音频已登记，详情页可重试（与现有 retranscribe 一致）；
- 完成后更新 `lastSyncSummary`（导入 N 条，跳过 M 条）。

### 2.2 文件与接口

**新增 `Services/Transfer/USBVolumeSyncEngine.swift`**
```swift
@Observable
final class USBVolumeSyncEngine {
    enum State { case idle, scanning, syncing(Int), completed(Int, Int), failed(String) }
    private(set) var state: State = .idle
    private(set) var lastSyncSummary: String?
    init(store: RecordingStore,
         storeDirectory: URL = AppEnvironment.defaultStoreDirectory(),
         transcriptionFactory: @escaping () -> FileTranscriptionEngine)
    func startMonitoring()   // 挂载监听 + 立即扫描现有卷
    func stopMonitoring()
    func syncNow() async     // 手动全量同步
}
```

### 2.3 接入

`App/FlashNoteApp.swift` 或 `AppEnvironment` 持有实例；macOS 侧 `.onAppear` 启动监听，工作台/设置页展示同步状态与「立即同步」入口（P0 UI 后续接入，本轮先交付引擎与单元测试）。

### 2.4 验收（macOS 真机）

1. 插入录音卡 → 自动发现 `record/` 新录音并导入、转写、进入听记列表（≤ 秒级复制）。
2. 重复插入 → 跳过已导入文件（无重复记录）。
3. 拔出卷不崩溃；拔插期间扫描安全。
4. 转写引擎未配置时：音频已导入并登记，状态 `.recording`，不阻塞。

## 3. 风险与边界

- **并发下载**：QS668 设备端仅支持单下载会话，分段「并行」不成立；本轮只做单会话吞吐优化（MTU 分片），不做多会话并发（避免设备端互扰）。
- **PHY**：iOS 27 SDK 无 PHY 编程 API，2M PHY 依赖系统自动协商；无法代码级强制，也无功能影响（1M 下 35min 录音下载仍可完成）。
- **USB 卷识别**：仅匹配含 `record/` 的卷，避免误同步普通 U 盘。
- iOS 沙箱无法挂载外部卷：USB 同步仅 macOS；iOS 走文件 App 导入（P0 UI 后续）。

## 4. 交付顺序

1. `BLETransport` 协议扩展 + `CB08Central` 实现 + Mock 同步（可编译可测）
2. `USBVolumeSyncEngine` 实现
3. `xcodegen generate` + macOS/iOS 构建验证
4. 文档与验收说明交付
