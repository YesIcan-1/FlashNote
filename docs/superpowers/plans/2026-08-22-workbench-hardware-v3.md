# FlashNote V3 工作台与硬件闭环 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 用原创工作台保留原 App 的录音能力，并将 CB08 的双通道 BLE、可靠下载、OPUS 解码和转写链路交付为可测试功能。

**Architecture:** `CB08Central` 负责两个通知特征，`CB08Device` 分别解析并发布设备事件；`DeviceDownloadTask` 统一下载阶段与进度；`OpusDecoder` 隔离 libopus 细节，输出 WAV 给既有文件转写引擎。工作台和设备控制台只消费 `DeviceViewModel` 的可观察状态。

**Tech Stack:** Swift 5.10、SwiftUI、CoreBluetooth、AVFoundation、Swift Testing、libopus 1.5.2（固定源码与 SHA-256）。

---

## 文件结构

- `Services/Device/BLETransport.swift`：双通知通道抽象。
- `Services/Device/CB08Central.swift`：AE22/AE23 的发现、订阅、分发与连接就绪判断。
- `Services/Device/CB08Device.swift`：独立帧解析、版本与录音状态回调、可取消下载。
- `Services/Device/DeviceDownloadTask.swift`：下载/解码/转写的阶段状态与进度编排。
- `Services/Device/DeviceTranscriptionService.swift`：以 `DeviceDownloadTask` 替代局部 continuation 状态，保存音频与转写。
- `FlashNoteCore/Sources/COpus/`：受控的 libopus C 桥接模块。
- `FlashNoteCore/Sources/FlashNoteCore/Audio/OpusDecoder.swift`：Swift OPUS 包解码和 WAV 编码接口。
- `Features/Device/DeviceViewModel.swift`、`Features/Device/DevicePanelView.swift`：设备状态、控制与任务列表。
- `Features/Workbench/WorkbenchView.swift`：原创桌面/移动工作台。
- `Features/Files/FileCenterView.swift`：本地/iCloud 来源切换、搜索和现有录音列表。
- `App/RootView.swift`、`DesignSystem/AppIcons.swift`：导航和图标。
- `Features/Import/ImportAudioView.swift`、`Features/Import/ImportTranscriptionViewModel.swift`：多选音频/视频导入队列。
- `Tests/CB08DeviceTests.swift`、`Tests/DeviceTranscriptionServiceTests.swift`、`Tests/DeviceViewModelTests.swift`：App 设备回归。
- `FlashNoteCore/Tests/FlashNoteCoreTests/OpusDecoderTests.swift`：核心音频回归。

### Task 1: 固定 libopus 与建立核心解码边界

**Files:**
- Create: `FlashNoteCore/Sources/COpus/include/COpus.h`
- Create: `FlashNoteCore/Sources/COpus/opus_shim.c`
- Create: `FlashNoteCore/Sources/FlashNoteCore/Audio/OpusDecoder.swift`
- Create: `FlashNoteCore/Tests/FlashNoteCoreTests/OpusDecoderTests.swift`
- Modify: `FlashNoteCore/Package.swift`
- Modify: `project.yml`

- [ ] **Step 1: 以官方 `xiph/opus` 的 tag `v1.5.2` 导入并校验源码。**

  记录发布 SHA-256 `65c1d2f78b9f2fb20082c38cbe47c951ad5839345876e46941612ee87f9a7ce1`；仅加入解码需要的许可、头文件和源文件，保留上游 BSD 许可文本。

- [ ] **Step 2: 写出会失败的核心测试。**

  ```swift
  @Test func rejectsPacketThatIsNotFortyBytes() throws {
      let decoder = try OpusDecoder(sampleRate: 16_000, channels: 1)
      #expect(throws: OpusDecodingError.invalidPacketLength(39)) {
          try decoder.decode(packet: Data(repeating: 0, count: 39))
      }
  }

  @Test func wavHeaderMatchesMono16kPCM() throws {
      let wav = try WAVEncoder.encode(samples: [0, 200, -200], sampleRate: 16_000, channels: 1)
      #expect(Array(wav.prefix(4)) == Array("RIFF".utf8))
      #expect(wav.subdata(in: 8..<12) == Data("WAVE".utf8))
      #expect(wav.count == 50)
  }
  ```

- [ ] **Step 3: 运行核心测试并确认 `OpusDecoder` 尚不存在而失败。**

  Run: `cd FlashNoteCore && swift test --filter OpusDecoderTests`

  Expected: 编译失败，提示 `cannot find 'OpusDecoder' in scope`。

- [ ] **Step 4: 实现 C 桥和 Swift API。**

  ```swift
  public enum OpusDecodingError: Error, Equatable {
      case invalidPacketLength(Int)
      case decoderCreationFailed(Int32)
      case decodeFailed(Int32)
  }

  public final class OpusDecoder {
      public init(sampleRate: Int32 = 16_000, channels: Int32 = 1) throws
      public func decode(packet: Data) throws -> [Int16]
  }

  public enum WAVEncoder {
      public static func encode(samples: [Int16], sampleRate: UInt32, channels: UInt16) throws -> Data
  }
  ```

  C 层只暴露 `fn_opus_decoder_create`、`fn_opus_decode`、`fn_opus_decoder_destroy` 三个无 Swift 所有权歧义的函数。`Package.swift` 中添加 `.target(name: "COpus", publicHeadersPath: "include")`，`FlashNoteCore` 依赖 `COpus`；`project.yml` 将 `FlashNoteCore/Sources/COpus` 纳入两个 static framework target。

- [ ] **Step 5: 运行核心测试。**

  Run: `cd FlashNoteCore && swift test --filter OpusDecoderTests`

  Expected: PASS。

- [ ] **Step 6: 提交核心音频边界。**

  ```bash
  git add FlashNoteCore project.yml
  git commit -m "feat: add libopus decoding boundary"
  ```

### Task 2: 双 BLE 通知与设备状态回填

**Files:**
- Modify: `Services/Device/BLETransport.swift`
- Modify: `Services/Device/CB08Central.swift`
- Modify: `Services/Device/CB08Device.swift`
- Modify: `Features/Device/DeviceViewModel.swift`
- Modify: `Tests/CB08DeviceTests.swift`

- [ ] **Step 1: 写会失败的双通道设备测试。**

  ```swift
  @Test func eventChannelUpdatesRecordStateWithoutCorruptingControlParser() {
      let (device, transport) = makeDevice()
      var state: UInt8?
      device.onRecordState = { state = $0 }
      transport.onEventNotify?(frameData(type: 3, cmd: 20, params: Data([2])))
      transport.onControlNotify?(frameData(type: 0, cmd: 4, params: Data([86])))
      #expect(state == 2)
  }

  @Test func versionResponseIsPublished() {
      let (device, transport) = makeDevice()
      var version: String?
      device.onFirmware = { version = $0 }
      transport.onControlNotify?(frameData(type: 0, cmd: 11, params: Data("V1.0.0".utf8)))
      #expect(version == "V1.0.0")
  }
  ```

- [ ] **Step 2: 运行测试确认当前单通道实现失败。**

  Run: `xcodebuild -project FlashNote.xcodeproj -scheme FlashNoteMac -destination 'platform=macOS' ONLY_ACTIVE_ARCH=YES ARCHS=arm64 test -only-testing:FlashNoteMacTests/CB08DeviceTests`

  Expected: 编译失败，`MockBLETransport` 没有事件通知回调。

- [ ] **Step 3: 实现明确的通道接口。**

  ```swift
  protocol BLETransport: AnyObject {
      func write(_ data: Data)
      func subscribe(
          onControlNotify: @escaping (Data) -> Void,
          onEventNotify: @escaping (Data) -> Void
      )
  }
  ```

  `CB08Central` 新增 `eventChar`（AE23），在两个 characteristic 都完成订阅确认后设为连接就绪；`didUpdateValueFor` 按 UUID 分发。`CB08Device` 用 `controlParser` 和 `eventParser` 分别解析，控制通道处理版本 `0:11`，事件通道处理录音状态 `3:20`。`DeviceViewModel` 将固件与录音状态映射为可观察属性，并在 `refreshInfo()` 请求版本和状态。

- [ ] **Step 4: 运行设备协议测试。**

  Run: 同 Step 2。

  Expected: PASS。

- [ ] **Step 5: 提交 BLE 状态闭环。**

  ```bash
  git add Services/Device Features/Device/DeviceViewModel.swift Tests/CB08DeviceTests.swift
  git commit -m "feat: surface CB08 event channel and device state"
  ```

### Task 3: 将设备下载改为阶段化、可取消任务

**Files:**
- Create: `Services/Device/DeviceDownloadTask.swift`
- Modify: `Services/Device/CB08Device.swift`
- Modify: `Services/Device/DeviceTranscriptionService.swift`
- Modify: `Tests/DeviceTranscriptionServiceTests.swift`

- [ ] **Step 1: 为压缩大小进度、阶段转换和候选回退写测试。**

  ```swift
  @Test func downloadProgressUsesCompressedFileSize() async throws {
      let (service, transport, _) = makeService()
      let file = CB08FileEntry(time: 173, size: 100, name: "note")
      var events: [DeviceDownloadTask.State] = []
      service.onTaskState = { events.append($0) }
      let task = Task { try await service.downloadAndTranscribe(file: file, title: "note") }
      try await Task.sleep(nanoseconds: 50_000_000)
      transport.onControlNotify?(frameData(type: 2, cmd: 4, params: Data(repeating: 1, count: 50)))
      #expect(events.contains(.downloading(progress: 0.5)))
      task.cancel()
  }
  ```

- [ ] **Step 2: 运行测试确认旧服务仍用 WAV 估算分母。**

  Run: `xcodebuild -project FlashNote.xcodeproj -scheme FlashNoteMac -destination 'platform=macOS' ONLY_ACTIVE_ARCH=YES ARCHS=arm64 test -only-testing:FlashNoteMacTests/DeviceTranscriptionServiceTests`

  Expected: FAIL，`onTaskState` 不存在。

- [ ] **Step 3: 实现任务模型和取消。**

  ```swift
  enum DeviceDownloadTask {
      enum State: Equatable {
          case queued
          case downloading(progress: Double)
          case decoding
          case transcribing
          case completed(recordingID: UUID)
          case failed(message: String)
          case cancelled
      }
  }
  ```

  `DeviceTranscriptionService` 对外发布 `onTaskState`，且将下载进度计算为 `min(1, Double(receivedBytes) / Double(max(file.size, 1)))`。开始候选顺序改为 `.opus`、`.wav`、原始名；取消时发 `abortImport()` 并恢复 continuation。OPUS 下载进入 `decoding`，WAV 下载跳过解码；转写前后分别发布 `transcribing` 和 `completed`。

- [ ] **Step 4: 运行下载服务测试。**

  Run: 同 Step 2。

  Expected: PASS。

- [ ] **Step 5: 提交下载状态机。**

  ```bash
  git add Services/Device Tests/DeviceTranscriptionServiceTests.swift
  git commit -m "feat: add staged cancellable device downloads"
  ```

### Task 4: 把 OPUS 下载接入 WAV 与转写

**Files:**
- Modify: `Services/Device/DeviceTranscriptionService.swift`
- Modify: `Tests/DeviceTranscriptionServiceTests.swift`

- [ ] **Step 1: 写 OPUS 下载会解码并将 WAV 交给转写引擎的测试。**

  ```swift
  @Test func opusDownloadWritesWAVBeforeTranscription() async throws {
      let decoder = MockDeviceAudioDecoder(wav: Data("RIFF-test".utf8))
      let service = makeService(decoder: decoder).service
      // 回放 .opus 候选成功的开始帧、40-byte 数据帧和结束帧。
      #expect(decoder.decodeCallCount == 1)
      #expect(decoder.lastOutputURL.pathExtension == "wav")
  }
  ```

- [ ] **Step 2: 实现可注入的音频解码依赖。**

  ```swift
  protocol DeviceAudioDecoding {
      func decodeToWAV(opusData: Data, outputURL: URL) throws
  }

  final class CB08OpusFileDecoder: DeviceAudioDecoding {
      func decodeToWAV(opusData: Data, outputURL: URL) throws
  }
  ```

  `CB08OpusFileDecoder` 以 40-byte 步进迭代原始数据，累积 `OpusDecoder.decode(packet:)` 输出的 PCM，最后调用 `WAVEncoder` 原子写入目标 URL。尾包不足 40 bytes 时抛可读的 `DeviceError.invalidOpusPacketLength`，不产生损坏的录音记录。

- [ ] **Step 3: 运行服务测试。**

  Run: 同 Task 3 Step 2。

  Expected: PASS。

- [ ] **Step 4: 提交 OPUS 下载链路。**

  ```bash
  git add Services/Device/DeviceTranscriptionService.swift Tests/DeviceTranscriptionServiceTests.swift
  git commit -m "feat: transcribe CB08 opus downloads"
  ```

### Task 5: 落地原创工作台和设备控制台

**Files:**
- Create: `Features/Workbench/WorkbenchView.swift`
- Modify: `Features/Device/DevicePanelView.swift`
- Modify: `Features/Device/DeviceViewModel.swift`
- Modify: `App/RootView.swift`
- Modify: `DesignSystem/AppIcons.swift`
- Create: `Tests/DeviceViewModelTests.swift`

- [ ] **Step 1: 写 ViewModel 状态映射测试。**

  ```swift
  @Test func completedDownloadUpdatesTaskSummary() {
      let vm = DeviceViewModel(store: InMemoryStore(), central: mockCentral)
      vm.applyTaskState(.completed(recordingID: UUID()))
      #expect(vm.taskSummary.phase == .completed)
      #expect(vm.statusText == "转写完成")
  }
  ```

- [ ] **Step 2: 实现不直接依赖协议的工作台状态。**

  `DeviceViewModel` 新增 `recordingState`、`taskSummary`、`canStartRecording`、`canPauseRecording`、`canSaveRecording` 和 `cancelActiveDownload()`。每项布尔值只从连接状态和记录状态推导，避免视图自行推断。

- [ ] **Step 3: 构建工作台视图。**

  `WorkbenchView` 为中央内容区，包含命令式“新建声音任务”、实时转写/导入/同传快捷操作、活动任务卡片和最近录音。macOS 的 `RootView` 使用“工作台、录音库、文件、设备、设置”路由并将同一 `DeviceViewModel` 注入工作台和设备页。设备页展示独立阶段文案、进度、取消、开始/暂停/继续/保存和同步文件；不要恢复功能宫格布局。

- [ ] **Step 4: 运行视图模型和应用测试。**

  Run: `xcodebuild -project FlashNote.xcodeproj -scheme FlashNoteMac -destination 'platform=macOS' ONLY_ACTIVE_ARCH=YES ARCHS=arm64 test -only-testing:FlashNoteMacTests/DeviceViewModelTests`

  Expected: PASS。

- [ ] **Step 5: 提交工作台与设备 UI。**

  ```bash
  git add App Features/Workbench Features/Device DesignSystem Tests/DeviceViewModelTests.swift
  git commit -m "feat: add workbench and device control surfaces"
  ```

### Task 6: 保留导入和文件中心能力

**Files:**
- Create: `Features/Files/FileCenterView.swift`
- Modify: `Features/Import/ImportAudioView.swift`
- Modify: `Features/Import/ImportTranscriptionViewModel.swift`
- Modify: `App/RootView.swift`
- Modify: `Tests/ImportTranscriptionViewModelTests.swift`

- [ ] **Step 1: 写多选导入队列测试。**

  ```swift
  @Test func batchImportCreatesOneRecordingForEachSource() async throws {
      let (vm, store) = makeVM()
      try await vm.importAndTranscribe(sourceURLs: [firstURL, secondURL])
      #expect(try store.fetchRecordings().count == 2)
  }
  ```

- [ ] **Step 2: 扩展导入和文件中心。**

  `ImportAudioView` 的文件选择允许 `.audio` 和 `.movie`、多选；ViewModel 按序处理 URL 并公开当前项目/总数。`FileCenterView` 提供“本地文件”和“iCloud 文件”来源切换、搜索和录音条目；在本轮尚无 CloudKit provider 时，iCloud 选项显示“同步即将启用，本地文件不受影响”，不得伪造云端文件存在。

- [ ] **Step 3: 运行导入回归。**

  Run: `xcodebuild -project FlashNote.xcodeproj -scheme FlashNoteMac -destination 'platform=macOS' ONLY_ACTIVE_ARCH=YES ARCHS=arm64 test -only-testing:FlashNoteMacTests/ImportTranscriptionViewModelTests`

  Expected: PASS。

- [ ] **Step 4: 提交导入与文件中心。**

  ```bash
  git add Features/Files Features/Import App/RootView.swift Tests/ImportTranscriptionViewModelTests.swift
  git commit -m "feat: add batch import and file center"
  ```

### Task 7: 全量回归与真机验收准备

**Files:**
- Modify: `README.md`
- Modify: `docs/superpowers/specs/2026-08-22-flashnote-workbench-hardware-v3-design.md`

- [ ] **Step 1: 更新运行与真机验收说明。**

  说明必须包括关闭厂商 App、使用 `open` 启动 macOS App、连接 → 读取状态 → 录音 → 同步 OPUS → 解码 → 转写 → 导出，以及下载每个阶段的预期 UI 文案。

- [ ] **Step 2: 运行所有自动化回归。**

  Run:

  ```bash
  cd FlashNoteCore && swift test && cd ..
  xcodebuild -project FlashNote.xcodeproj -scheme FlashNoteMac -destination 'platform=macOS' ONLY_ACTIVE_ARCH=YES ARCHS=arm64 test
  xcodebuild -project FlashNote.xcodeproj -scheme FlashNote -sdk iphoneos CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=YES ARCHS=arm64 build
  ```

  Expected: 三个命令均成功，且没有架构或 TCC plist 回归。

- [ ] **Step 3: 提交验证文档。**

  ```bash
  git add README.md docs/superpowers/specs/2026-08-22-flashnote-workbench-hardware-v3-design.md
  git commit -m "docs: add workbench hardware verification"
  ```
