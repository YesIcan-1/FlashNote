# FlashNote Core 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 构建 `FlashNoteCore` 纯 Swift 包——包含领域模型、转写引擎协议与转写服务、OpenAI 兼容 LLM 客户端、纪要生成器（内置三风格模板 + 自定义模板）、长文本分块、文件存储层，全部以 TDD 方式在命令行完成并测试通过（无需 Xcode）。

**Architecture:** 核心层与 UI/平台 SDK 完全解耦。`TranscriptionEngine` 协议是转写通道的可插拔缝（App 层将提供 Apple Speech / Whisper / 云端三个实现，本包用 Mock 引擎测试服务逻辑）；`LLMClient` 协议封装 OpenAI 兼容 Chat Completions；`MinutesGenerator` 组合模板 + LLM + 分块器生成结构化纪要；`RecordingStore` 协议提供数据访问抽象，`FileRecordingStore` 是 JSON 文件实现（后续 CloudKit 实现替换时 UI 无感知）。

**Tech Stack:** Swift 6.3 工具链、Swift Package（tools-version 5.10，Swift 5 语言模式以规避严格并发摩擦）、Swift Testing（本机无 Xcode/XCTest，见下方约定）、URLSession + URLProtocol（测试桩）、Foundation Codable。

## 测试框架约定（本机环境决定）

本机仅安装 Command Line Tools（无 Xcode），其 macOS SDK **不含 XCTest.framework**（XCTest 只随 Xcode 一起提供）。因此本计划的全部测试使用 **Swift Testing**——它随 Swift 工具链一起发布，不依赖 Xcode。

本机运行 `swift test` 必须显式传入框架路径与 rpath 标志（已验证可行）：

```bash
cd FlashNoteCore && swift test \
  -Xswiftc -F/Library/Developer/CommandLineTools/Library/Developer/Frameworks \
  -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/Frameworks \
  -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/usr/lib
```

注意：`-F` 标志必须使用紧贴形式（`-F/path`），不能写成 `-F /path`，否则 SwiftPM 会拒绝。装有 Xcode 的机器上直接运行 `swift test` 即可，无需任何标志。

XCTest → Swift Testing 映射：

| XCTest | Swift Testing |
| --- | --- |
| `import XCTest` + `final class XTests: XCTestCase` | `import Testing` + `struct XTests`（或 `@Suite struct`） |
| `func testFoo() { XCTAssertEqual(a, b) }` | `@Test func foo() { #expect(a == b) }` |
| `XCTAssertTrue(x)` / `XCTAssertFalse(x)` | `#expect(x)` / `#expect(!x)` |
| `XCTAssertNil(x)` / `XCTAssertNotNil(x)` | `#expect(x == nil)` / `#expect(x != nil)` |
| `XCTAssertGreaterThan(a, b)` / `XCTAssertLessThanOrEqual(a, b)` | `#expect(a > b)` / `#expect(a <= b)` |
| `XCTAssertThrowsError(expr) { error in XCTAssertEqual(error as? T, e) }` | `#expect(throws: T.self) { try expr }`，或 do/catch + `Issue.record` 做具体 case 检查 |
| `XCTAssertEqual(a, b)`（数组 / 字符串） | `#expect(a == b)` |
| `setUp()` / `tearDown()` 实例生命周期 | `init() throws` / `deinit` |
| 异步测试 | `@Test func foo() async throws` 原生支持 |
| `XCTFail("msg")` | `Issue.record("msg")` |

下文 Task 1-11 中的所有测试代码片段均以 Swift Testing 编写；生产代码不受影响。

**环境前置检查（Step 1 中执行）：**
- 本机已安装 Swift 工具链（`swift --version` 输出 Swift 6.x）。
- 本机**未安装 Xcode**（`xcodebuild` 不可用）——本计划全部命令只依赖 `swift build` / `swift test`，不受影响。
- 所有命令在仓库根目录执行；包位于 `FlashNoteCore/`。

---

## 文件结构

```
FlashNoteCore/
├── Package.swift                          # tools-version 5.10, iOS 17 / macOS 14
├── Sources/FlashNoteCore/
│   ├── Models/
│   │   ├── Recording.swift                # Recording + RecordingStatus（markTranscribed/markSummarized）
│   │   ├── Transcript.swift               # Transcript + TranscriptSegment（fullText 聚合）
│   │   └── Folder.swift                   # Folder
│   ├── Transcription/
│   │   ├── TranscriptionEngine.swift      # 协议 + TranscriptionError
│   │   └── TranscriptionService.swift     # 引擎回调 → 段落追加（线程安全）
│   ├── AI/
│   │   ├── LLMModels.swift                # ChatMessage / LLMConfiguration
│   │   ├── LLMClient.swift                # LLMClient 协议 + LLMError + OpenAICompatibleClient
│   │   ├── TranscriptChunker.swift        # 长文本按句切块
│   │   ├── MinutesTemplate.swift          # 模板模型 + 三个内置模板
│   │   └── MinutesGenerator.swift         # Minutes / MinutesSection + 生成器 + 分节解析
│   └── Store/
│       ├── RecordingStore.swift           # 协议 + StoreError
│       └── FileRecordingStore.swift       # JSON 文件实现
└── Tests/FlashNoteCoreTests/
    ├── ModelsTests.swift                  # Task 2-4
    ├── TranscriptionServiceTests.swift    # Task 5
    ├── OpenAICompatibleClientTests.swift  # Task 6（含 MockURLProtocol）
    ├── TranscriptChunkerTests.swift       # Task 7
    ├── MinutesTemplateTests.swift         # Task 8
    ├── MinutesGeneratorTests.swift        # Task 9
    ├── FileRecordingStoreTests.swift      # Task 10
    └── IntegrationTests.swift             # Task 11
```

**本计划之外（需要 Xcode，后续单独计划）：** SwiftUI 界面、AVAudioEngine 录音、SFSpeechRecognizer / Whisper / 云端 ASR 引擎实现、CloudKit + iCloud Drive 同步、全文搜索、App 图标与打包。

---

### Task 1: 包脚手架

**Files:**
- Create: `FlashNoteCore/Package.swift`
- Create: `FlashNoteCore/Sources/FlashNoteCore/FlashNoteCore.swift`
- Create: `FlashNoteCore/Tests/FlashNoteCoreTests/FlashNoteCoreTests.swift`

- [ ] **Step 1: 验证工具链并创建目录**

```bash
swift --version
mkdir -p FlashNoteCore/Sources/FlashNoteCore FlashNoteCore/Tests/FlashNoteCoreTests
```
Expected: 输出 Swift 6.x 版本信息；目录创建成功。

- [ ] **Step 2: 编写 Package.swift**

```swift
// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "FlashNoteCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "FlashNoteCore", targets: ["FlashNoteCore"])
    ],
    targets: [
        .target(name: "FlashNoteCore"),
        .testTarget(name: "FlashNoteCoreTests", dependencies: ["FlashNoteCore"])
    ]
)
```

- [ ] **Step 3: 写最小源文件与测试**

`FlashNoteCore/Sources/FlashNoteCore/FlashNoteCore.swift`:

```swift
/// FlashNote 核心领域层。所有平台无关的逻辑（模型、转写服务、AI、存储）都在此包中。
public enum FlashNoteCore {
    public static let version = "0.1.0"
}
```

`FlashNoteCore/Tests/FlashNoteCoreTests/FlashNoteCoreTests.swift`:

```swift
// XCTest is unavailable on machines with only Command Line Tools (no Xcode);
// Swift Testing ships with the Swift toolchain itself.
import Testing
@testable import FlashNoteCore

struct FlashNoteCoreTests {
    @Test func version() {
        #expect(FlashNoteCore.version == "0.1.0")
    }
}
```

- [ ] **Step 4: 构建并测试**

```bash
cd FlashNoteCore && swift build && swift test \
  -Xswiftc -F/Library/Developer/CommandLineTools/Library/Developer/Frameworks \
  -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/Frameworks \
  -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/usr/lib
```
Expected: 构建成功；`FlashNoteCoreTests.version` 通过。

- [ ] **Step 5: 提交**

```bash
cd .. && git add FlashNoteCore && git commit -m "feat: scaffold FlashNoteCore package"
```

---

### Task 2: Recording 模型

**Files:**
- Create: `FlashNoteCore/Sources/FlashNoteCore/Models/Recording.swift`
- Test: `FlashNoteCore/Tests/FlashNoteCoreTests/ModelsTests.swift`

- [ ] **Step 1: 写失败测试**

`FlashNoteCore/Tests/FlashNoteCoreTests/ModelsTests.swift`:

```swift
import Testing
@testable import FlashNoteCore

struct ModelsTests {
    @Test func recordingDefaults() {
        let rec = Recording(title: "周会纪要")
        #expect(rec.status == .recording)
        #expect(rec.duration == 0)
        #expect(rec.folderID == nil)
        #expect(rec.audioFilename == nil)
        #expect(rec.title == "周会纪要")
        #expect(rec.updatedAt == rec.createdAt)
    }

    @Test func markTranscribed() {
        var rec = Recording(title: "x", createdAt: Date(timeIntervalSince1970: 1000))
        rec.markTranscribed()
        #expect(rec.status == .transcribed)
        #expect(rec.updatedAt > rec.createdAt)
    }

    @Test func markSummarized() {
        var rec = Recording(title: "x", createdAt: Date(timeIntervalSince1970: 1000))
        rec.markSummarized()
        #expect(rec.status == .summarized)
        #expect(rec.updatedAt > rec.createdAt)
    }

    @Test func recordingCodableRoundTrip() throws {
        let rec = Recording(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            title: "测试",
            folderID: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            audioFilename: "abc.m4a",
            duration: 65.5,
            status: .transcribed,
            createdAt: Date(timeIntervalSince1970: 1000),
            updatedAt: Date(timeIntervalSince1970: 2000)
        )
        let data = try JSONEncoder().encode(rec)
        let decoded = try JSONDecoder().decode(Recording.self, from: data)
        #expect(decoded == rec)
    }
}
```

- [ ] **Step 2: 运行确认失败**

```bash
cd FlashNoteCore && swift test \
  -Xswiftc -F/Library/Developer/CommandLineTools/Library/Developer/Frameworks \
  -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/Frameworks \
  -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/usr/lib
```
Expected: 编译失败——找不到 `Recording` 类型。

- [ ] **Step 3: 实现 Recording**

`FlashNoteCore/Sources/FlashNoteCore/Models/Recording.swift`:

```swift
import Foundation

/// 录音的流转状态。
public enum RecordingStatus: String, Codable, Sendable {
    case recording
    case transcribed
    case summarized
}

/// 一条录音记录（结构化数据；音频文件本身由 App 层存放于 iCloud Drive）。
public struct Recording: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var folderID: UUID?
    public var audioFilename: String?
    public var duration: TimeInterval
    public var status: RecordingStatus
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        title: String,
        folderID: UUID? = nil,
        audioFilename: String? = nil,
        duration: TimeInterval = 0,
        status: RecordingStatus = .recording,
        createdAt: Date = Date(),
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.folderID = folderID
        self.audioFilename = audioFilename
        self.duration = duration
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
    }

    public mutating func markTranscribed() {
        status = .transcribed
        updatedAt = Date()
    }

    public mutating func markSummarized() {
        status = .summarized
        updatedAt = Date()
    }
}
```

- [ ] **Step 4: 运行确认通过**

```bash
cd FlashNoteCore && swift test \
  -Xswiftc -F/Library/Developer/CommandLineTools/Library/Developer/Frameworks \
  -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/Frameworks \
  -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/usr/lib
```
Expected: `ModelsTests` 全部通过（4 个测试）。

- [ ] **Step 5: 提交**

```bash
cd .. && git add FlashNoteCore && git commit -m "feat: add Recording model"
```

---

### Task 3: Transcript 模型

**Files:**
- Create: `FlashNoteCore/Sources/FlashNoteCore/Models/Transcript.swift`
- Modify: `FlashNoteCore/Tests/FlashNoteCoreTests/ModelsTests.swift`（追加测试）

- [ ] **Step 1: 追加失败测试**

在 `ModelsTests.swift` 的类末尾（最后一个 `}` 之前）追加：

```swift
    @Test func segmentCodable() throws {
        let seg = TranscriptSegment(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
            startTime: 12.5,
            endTime: 15.0,
            speaker: "李娜",
            text: "纪要模板建议做成可自定义的。",
            isFinal: true
        )
        let data = try JSONEncoder().encode(seg)
        let decoded = try JSONDecoder().decode(TranscriptSegment.self, from: data)
        #expect(decoded == seg)
    }

    @Test func transcriptAppendAndFullText() {
        var t = Transcript(recordingID: UUID(), language: "zh-Hans")
        #expect(t.fullText == "")
        t.append(TranscriptSegment(startTime: 0, text: "第一句。"))
        t.append(TranscriptSegment(startTime: 2, text: "第二句。"))
        #expect(t.segments.count == 2)
        #expect(t.fullText == "第一句。\n第二句。")
        #expect(t.language == "zh-Hans")
    }
```

- [ ] **Step 2: 运行确认失败**

```bash
cd FlashNoteCore && swift test \
  -Xswiftc -F/Library/Developer/CommandLineTools/Library/Developer/Frameworks \
  -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/Frameworks \
  -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/usr/lib
```
Expected: 编译失败——找不到 `TranscriptSegment` / `Transcript`。

- [ ] **Step 3: 实现 Transcript**

`FlashNoteCore/Sources/FlashNoteCore/Models/Transcript.swift`:

```swift
import Foundation

/// 转写的一个段落（时间戳 + 可选说话人 + 文本）。
public struct TranscriptSegment: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var startTime: TimeInterval
    public var endTime: TimeInterval?
    public var speaker: String?
    public var text: String
    public var isFinal: Bool

    public init(
        id: UUID = UUID(),
        startTime: TimeInterval,
        endTime: TimeInterval? = nil,
        speaker: String? = nil,
        text: String,
        isFinal: Bool = true
    ) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.speaker = speaker
        self.text = text
        self.isFinal = isFinal
    }
}

/// 一次录音的完整转写（段落集合）。
public struct Transcript: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var recordingID: UUID
    public var segments: [TranscriptSegment]
    public var language: String
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        recordingID: UUID,
        segments: [TranscriptSegment] = [],
        language: String = "zh-Hans",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.recordingID = recordingID
        self.segments = segments
        self.language = language
        self.createdAt = createdAt
    }

    /// 全部段落文本，以换行连接（作为 LLM 输入）。
    public var fullText: String {
        segments.map(\.text).joined(separator: "\n")
    }

    public mutating func append(_ segment: TranscriptSegment) {
        segments.append(segment)
    }
}
```

- [ ] **Step 4: 运行确认通过**

```bash
cd FlashNoteCore && swift test \
  -Xswiftc -F/Library/Developer/CommandLineTools/Library/Developer/Frameworks \
  -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/Frameworks \
  -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/usr/lib
```
Expected: 全部测试通过。

- [ ] **Step 5: 提交**

```bash
cd .. && git add FlashNoteCore && git commit -m "feat: add Transcript model"
```

---

### Task 4: Folder 模型

**Files:**
- Create: `FlashNoteCore/Sources/FlashNoteCore/Models/Folder.swift`
- Modify: `FlashNoteCore/Tests/FlashNoteCoreTests/ModelsTests.swift`（追加测试）

- [ ] **Step 1: 追加失败测试**

```swift
    @Test func folderCodable() throws {
        let folder = Folder(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
            name: "工作",
            parentID: nil,
            colorIndex: 1,
            createdAt: Date(timeIntervalSince1970: 100)
        )
        let data = try JSONEncoder().encode(folder)
        let decoded = try JSONDecoder().decode(Folder.self, from: data)
        #expect(decoded == folder)
        #expect(decoded.name == "工作")
    }
```

- [ ] **Step 2: 运行确认失败**

```bash
cd FlashNoteCore && swift test \
  -Xswiftc -F/Library/Developer/CommandLineTools/Library/Developer/Frameworks \
  -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/Frameworks \
  -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/usr/lib
```
Expected: 编译失败——找不到 `Folder`。

- [ ] **Step 3: 实现 Folder**

`FlashNoteCore/Sources/FlashNoteCore/Models/Folder.swift`:

```swift
import Foundation

/// 录音文件夹。V1 仅支持单层（parentID 预留为 nil）。
public struct Folder: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var parentID: UUID?
    public var colorIndex: Int
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        parentID: UUID? = nil,
        colorIndex: Int = 0,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.parentID = parentID
        self.colorIndex = colorIndex
        self.createdAt = createdAt
    }
}
```

- [ ] **Step 4: 运行确认通过**

```bash
cd FlashNoteCore && swift test \
  -Xswiftc -F/Library/Developer/CommandLineTools/Library/Developer/Frameworks \
  -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/Frameworks \
  -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/usr/lib
```
Expected: 全部测试通过。

- [ ] **Step 5: 提交**

```bash
cd .. && git add FlashNoteCore && git commit -m "feat: add Folder model"
```

---

### Task 5: 转写引擎协议与转写服务

**Files:**
- Create: `FlashNoteCore/Sources/FlashNoteCore/Transcription/TranscriptionEngine.swift`
- Create: `FlashNoteCore/Sources/FlashNoteCore/Transcription/TranscriptionService.swift`
- Create: `FlashNoteCore/Tests/FlashNoteCoreTests/TranscriptionServiceTests.swift`

- [ ] **Step 1: 写失败测试**

`FlashNoteCore/Tests/FlashNoteCoreTests/TranscriptionServiceTests.swift`:

```swift
import Testing
@testable import FlashNoteCore

/// 测试替身：start 时同步发出两个段落。
final class MockTranscriptionEngine: TranscriptionEngine {
    let displayName = "MockEngine"
    let isRealtime = true
    var onSegment: ((TranscriptSegment) -> Void)?
    var onError: ((Error) -> Void)?
    private(set) var started = false
    private(set) var cancelled = false

    func start() throws {
        started = true
        onSegment?(TranscriptSegment(startTime: 0, text: "你好。"))
        onSegment?(TranscriptSegment(startTime: 2, text: "这是一段测试转写。"))
    }

    func cancel() {
        cancelled = true
    }
}

struct TranscriptionServiceTests {
    @Test func beginAppendsSegments() throws {
        let engine = MockTranscriptionEngine()
        let service = TranscriptionService(recordingID: UUID(), engine: engine)
        try service.begin()
        #expect(engine.started)
        #expect(service.transcript.segments.count == 2)
        #expect(service.transcript.fullText == "你好。\n这是一段测试转写。")
    }

    @Test func finishReturnsTranscript() throws {
        let service = TranscriptionService(recordingID: UUID(), engine: MockTranscriptionEngine())
        try service.begin()
        let transcript = service.finish()
        #expect(transcript.segments.count == 2)
    }

    @Test func cancelStopsEngine() throws {
        let engine = MockTranscriptionEngine()
        let service = TranscriptionService(recordingID: UUID(), engine: engine)
        try service.begin()
        service.cancel()
        #expect(engine.cancelled)
    }

    @Test func engineErrorIsCaptured() throws {
        final class FailingEngine: TranscriptionEngine {
            let displayName = "Failing"
            let isRealtime = false
            var onSegment: ((TranscriptSegment) -> Void)?
            var onError: ((Error) -> Void)?
            func start() throws {
                onError?(TranscriptionError.engineFailed("boom"))
            }
            func cancel() {}
        }
        let service = TranscriptionService(recordingID: UUID(), engine: FailingEngine())
        try service.begin()
        #expect(service.lastError as? TranscriptionError == .engineFailed("boom"))
    }

    @Test func nonFinalSegmentsAreDropped() throws {
        final class PartialEngine: TranscriptionEngine {
            let displayName = "Partial"
            let isRealtime = true
            var onSegment: ((TranscriptSegment) -> Void)?
            var onError: ((Error) -> Void)?
            func start() throws {
                onSegment?(TranscriptSegment(startTime: 0, text: "临时", isFinal: false))
                onSegment?(TranscriptSegment(startTime: 0, text: "你好。", isFinal: true))
                onSegment?(TranscriptSegment(startTime: 2, text: "还在想…", isFinal: false))
            }
            func cancel() {}
        }
        let service = TranscriptionService(recordingID: UUID(), engine: PartialEngine())
        try service.begin()
        #expect(service.transcript.segments.count == 1)
        #expect(service.transcript.fullText == "你好。")
    }

    @Test func asyncSegmentAfterBegin() async throws {
        final class AsyncEngine: TranscriptionEngine {
            let displayName = "Async"
            let isRealtime = true
            var onSegment: ((TranscriptSegment) -> Void)?
            var onError: ((Error) -> Void)?
            func start() throws {
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) { [weak self] in
                    self?.onSegment?(TranscriptSegment(startTime: 0, text: "异步段落。"))
                }
            }
            func cancel() {}
        }
        let service = TranscriptionService(recordingID: UUID(), engine: AsyncEngine())
        try service.begin()
        try await Task.sleep(nanoseconds: 300_000_000)
        #expect(service.transcript.segments.count == 1)
        #expect(service.transcript.fullText == "异步段落。")
    }

    @Test func concurrentAppendsStress() throws {
        final class BurstEngine: TranscriptionEngine {
            let displayName = "Burst"
            let isRealtime = true
            var onSegment: ((TranscriptSegment) -> Void)?
            var onError: ((Error) -> Void)?
            func start() throws {
                let total = 200
                DispatchQueue.concurrentPerform(iterations: total) { i in
                    self.onSegment?(TranscriptSegment(startTime: TimeInterval(i), text: "段\(i)"))
                }
            }
            func cancel() {}
        }
        let service = TranscriptionService(recordingID: UUID(), engine: BurstEngine())
        try service.begin()
        // concurrentPerform 同步阻塞至全部完成；NSLock 保护下不应丢失任何段落
        #expect(service.transcript.segments.count == 200)
    }

    @Test func beginThrowIsRecorded() {
        final class ThrowingEngine: TranscriptionEngine {
            let displayName = "Throwing"
            let isRealtime = false
            var onSegment: ((TranscriptSegment) -> Void)?
            var onError: ((Error) -> Void)?
            func start() throws { throw TranscriptionError.engineUnavailable }
            func cancel() {}
        }
        let service = TranscriptionService(recordingID: UUID(), engine: ThrowingEngine())
        #expect(throws: TranscriptionError.self) { try service.begin() }
        #expect(service.lastError as? TranscriptionError == .engineUnavailable)
    }
}
```

- [ ] **Step 2: 运行确认失败**

```bash
cd FlashNoteCore && swift test \
  -Xswiftc -F/Library/Developer/CommandLineTools/Library/Developer/Frameworks \
  -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/Frameworks \
  -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/usr/lib
```
Expected: 编译失败——找不到 `TranscriptionEngine` / `TranscriptionService`。

- [ ] **Step 3: 实现协议与服务**

`FlashNoteCore/Sources/FlashNoteCore/Transcription/TranscriptionEngine.swift`:

```swift
import Foundation

public enum TranscriptionError: Error, Equatable {
    case engineUnavailable
    case permissionDenied
    case invalidState(String)
    case engineFailed(String)
}

/// 转写通道的可插拔缝。App 层提供 Apple Speech（实时）、whisper.cpp（整段）、云端 ASR 三个实现。
public protocol TranscriptionEngine: AnyObject {
    var displayName: String { get }
    var isRealtime: Bool { get }
    func start() throws
    func cancel()
    var onSegment: ((TranscriptSegment) -> Void)? { get set }
    var onError: ((Error) -> Void)? { get set }
}
```

`FlashNoteCore/Sources/FlashNoteCore/Transcription/TranscriptionService.swift`:

```swift
import Foundation

/// 编排单个引擎：把引擎回调的段落累积进 Transcript，并对回调做线程安全保护。
///
/// 段落契约（防止流式引擎 partial→final 重复文本）：
/// 本服务只追加 `isFinal == true` 的段落；非最终段（`isFinal == false`）由
/// App 层引擎实现自行聚合（如用相同 startTime 替换临时段），仅在确定时
/// 以 `isFinal == true` 回调。Mock 引擎（本包测试）直接回调最终段落。
///
/// 线程安全：所有状态（_transcript / _lastError）的读写都在 lock 保护下进行；
/// 引擎回调可来自任意队列。调用方应在调用 finish() 前先停止引擎，
/// 确保没有回调在途（晚到的段落不会进入已返回的快照）。
public final class TranscriptionService {
    private var _transcript: Transcript
    private var _lastError: Error?

    private let engine: TranscriptionEngine
    private let lock = NSLock()

    public init(recordingID: UUID, engine: TranscriptionEngine, language: String = "zh-Hans") {
        self._transcript = Transcript(recordingID: recordingID, language: language)
        self.engine = engine
        engine.onSegment = { [weak self] segment in
            guard let self, segment.isFinal else { return }
            self.lock.lock()
            self._transcript.append(segment)
            self.lock.unlock()
        }
        engine.onError = { [weak self] error in
            self?.setLastError(error)
        }
    }

    public var transcript: Transcript {
        lock.lock(); defer { lock.unlock() }
        return _transcript
    }

    public var lastError: Error? {
        lock.lock(); defer { lock.unlock() }
        return _lastError
    }

    public func begin() throws {
        do {
            try engine.start()
        } catch {
            setLastError(error)
            throw error
        }
    }

    public func cancel() {
        engine.cancel()
    }

    /// 结束转写，返回最终 Transcript 快照。
    public func finish() -> Transcript {
        transcript
    }

    private func setLastError(_ error: Error) {
        lock.lock()
        _lastError = error
        lock.unlock()
    }
}
```

- [ ] **Step 4: 运行确认通过**

```bash
cd FlashNoteCore && swift test \
  -Xswiftc -F/Library/Developer/CommandLineTools/Library/Developer/Frameworks \
  -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/Frameworks \
  -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/usr/lib
```
Expected: `TranscriptionServiceTests` 全部通过（8 个测试）。

- [ ] **Step 5: 提交**

```bash
cd .. && git add FlashNoteCore && git commit -m "feat: add transcription engine protocol and service"
```

---

### Task 6: OpenAI 兼容 LLM 客户端

**Files:**
- Create: `FlashNoteCore/Sources/FlashNoteCore/AI/LLMModels.swift`
- Create: `FlashNoteCore/Sources/FlashNoteCore/AI/LLMClient.swift`
- Create: `FlashNoteCore/Tests/FlashNoteCoreTests/OpenAICompatibleClientTests.swift`

- [ ] **Step 1: 写失败测试**

`FlashNoteCore/Tests/FlashNoteCoreTests/OpenAICompatibleClientTests.swift`:

```swift
import Testing
@testable import FlashNoteCore

/// URLProtocol 桩：捕获请求并返回预设响应。
final class MockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = MockURLProtocol.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

struct OpenAICompatibleClientTests {
    private func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    private func makeConfig() -> LLMConfiguration {
        LLMConfiguration(
            baseURL: URL(string: "https://api.deepseek.com")!,
            apiKey: "test-key",
            model: "deepseek-chat",
            temperature: 0.3
        )
    }

    @Test func completeParsesContent() async throws {
        let json = """
        {"choices":[{"message":{"role":"assistant","content":"会议结论：通过。"}}]}
        """
        MockURLProtocol.requestHandler = { request in
            #expect(request.url?.path == "/chat/completions")
            #expect(request.httpMethod == "POST")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-key")
            let body = request.httpBody ?? Data()
            let obj = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            #expect(obj?["model"] as? String == "deepseek-chat")
            #expect(obj?["stream"] as? Bool == false)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, json.data(using: .utf8)!)
        }
        let client = OpenAICompatibleClient(configuration: makeConfig(), session: makeSession())
        let result = try await client.complete(messages: [ChatMessage(role: .user, content: "hi")])
        #expect(result == "会议结论：通过。")
        #expect(client.modelName == "deepseek-chat")
    }

    @Test func completeThrowsOnHTTPError() async {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }
        let client = OpenAICompatibleClient(configuration: makeConfig(), session: makeSession())
        do {
            _ = try await client.complete(messages: [])
            Issue.record("应当抛出错误")
        } catch let error as LLMError {
            #expect(error == .httpStatus(401))
        } catch {
            Issue.record("错误的错误类型: \(error)")
        }
    }

    @Test func streamParsesSSE() async throws {
        let sse = """
        data: {"choices":[{"delta":{"content":"你"}}]}

        data: {"choices":[{"delta":{"content":"好"}}]}

        data: [DONE]

        """
        MockURLProtocol.requestHandler = { request in
            let obj = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any]
            #expect(obj?["stream"] as? Bool == true)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, sse.data(using: .utf8)!)
        }
        let client = OpenAICompatibleClient(configuration: makeConfig(), session: makeSession())
        var collected = ""
        for try await piece in client.stream(messages: []) {
            collected += piece
        }
        #expect(collected == "你好")
    }

    @Test func streamThrowsOnHTTPError() async {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 429, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }
        let client = OpenAICompatibleClient(configuration: makeConfig(), session: makeSession())
        do {
            for try await _ in client.stream(messages: []) {}
            Issue.record("应当抛出错误")
        } catch let error as LLMError {
            #expect(error == .httpStatus(429))
        } catch {
            Issue.record("错误的错误类型: \(error)")
        }
    }
}
```

- [ ] **Step 2: 运行确认失败**

```bash
cd FlashNoteCore && swift test \
  -Xswiftc -F/Library/Developer/CommandLineTools/Library/Developer/Frameworks \
  -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/Frameworks \
  -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/usr/lib
```
Expected: 编译失败——找不到 `ChatMessage` / `LLMConfiguration` / `LLMClient` / `OpenAICompatibleClient`。

- [ ] **Step 3: 实现模型与客户端**

`FlashNoteCore/Sources/FlashNoteCore/AI/LLMModels.swift`:

```swift
import Foundation

/// Chat 消息。
public struct ChatMessage: Codable, Equatable, Sendable {
    public enum Role: String, Codable, Sendable {
        case system, user, assistant
    }

    public var role: Role
    public var content: String

    public init(role: Role, content: String) {
        self.role = role
        self.content = content
    }
}

/// OpenAI 兼容服务的连接配置（用户可在设置中修改；apiKey 由 App 层存 Keychain）。
public struct LLMConfiguration: Codable, Equatable, Sendable {
    public var baseURL: URL
    public var apiKey: String
    public var model: String
    public var temperature: Double

    public init(
        baseURL: URL = URL(string: "https://api.deepseek.com")!,
        apiKey: String,
        model: String = "deepseek-chat",
        temperature: Double = 0.3
    ) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.model = model
        self.temperature = temperature
    }
}
```

`FlashNoteCore/Sources/FlashNoteCore/AI/LLMClient.swift`:

```swift
import Foundation

public enum LLMError: Error, Equatable {
    case httpStatus(Int)
    case invalidResponse
}

public protocol LLMClient: Sendable {
    var modelName: String { get }
    /// 非流式完成。
    func complete(messages: [ChatMessage]) async throws -> String
    /// 流式完成（SSE），逐段产出文本增量。
    func stream(messages: [ChatMessage]) -> AsyncThrowingStream<String, Error>
}

/// OpenAI 兼容 Chat Completions 客户端（DeepSeek / OpenAI / 通义 / Ollama 等均可通过 Base URL 接入）。
public final class OpenAICompatibleClient: LLMClient, @unchecked Sendable {
    public let modelName: String
    private let configuration: LLMConfiguration
    private let session: URLSession

    public init(configuration: LLMConfiguration, session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
        self.modelName = configuration.model
    }

    public func complete(messages: [ChatMessage]) async throws -> String {
        let request = try makeRequest(messages: messages, stream: false)
        let (data, response) = try await session.data(for: request)
        try Self.validate(response)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String,
              !content.isEmpty else {
            throw LLMError.invalidResponse
        }
        return content
    }

    public func stream(messages: [ChatMessage]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try self.makeRequest(messages: messages, stream: true)
                    let (bytes, response) = try await self.session.bytes(for: request)
                    try Self.validate(response)
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if payload == "[DONE]" { break }
                        guard let data = payload.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let choices = json["choices"] as? [[String: Any]],
                              let delta = choices.first?["delta"] as? [String: Any],
                              let content = delta["content"] as? String else { continue }
                        continuation.yield(content)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func makeRequest(messages: [ChatMessage], stream: Bool) throws -> URLRequest {
        let url = configuration.baseURL.appendingPathComponent("chat/completions")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        let body: [String: Any] = [
            "model": configuration.model,
            "messages": messages.map { ["role": $0.role.rawValue, "content": $0.content] },
            "temperature": configuration.temperature,
            "stream": stream
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private static func validate(_ response: URLResponse) throws {
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw LLMError.httpStatus(http.statusCode)
        }
    }
}
```

- [ ] **Step 4: 运行确认通过**

```bash
cd FlashNoteCore && swift test \
  -Xswiftc -F/Library/Developer/CommandLineTools/Library/Developer/Frameworks \
  -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/Frameworks \
  -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/usr/lib
```
Expected: `OpenAICompatibleClientTests` 全部通过（4 个测试）。

- [ ] **Step 5: 提交**

```bash
cd .. && git add FlashNoteCore && git commit -m "feat: add OpenAI-compatible LLM client"
```

---

### Task 7: 转写文本分块器

**Files:**
- Create: `FlashNoteCore/Sources/FlashNoteCore/AI/TranscriptChunker.swift`
- Create: `FlashNoteCore/Tests/FlashNoteCoreTests/TranscriptChunkerTests.swift`

- [ ] **Step 1: 写失败测试**

`FlashNoteCore/Tests/FlashNoteCoreTests/TranscriptChunkerTests.swift`:

```swift
import Testing
@testable import FlashNoteCore

struct TranscriptChunkerTests {
    @Test func emptyText() {
        #expect(TranscriptChunker().chunk("") == [])
    }

    @Test func shortTextSingleChunk() {
        let text = "第一句。第二句！第三句？"
        #expect(TranscriptChunker(maxChars: 100).chunk(text) == [text])
    }

    @Test func longTextSplitsAtSentenceBoundaries() {
        var text = ""
        for i in 0..<50 {
            text += "第\(i)句是一段完整的话。"
        }
        let chunks = TranscriptChunker(maxChars: 100).chunk(text)
        #expect(chunks.count > 1)
        for chunk in chunks {
            #expect(chunk.count <= 100)
            #expect(chunk.hasSuffix("。") || chunk.hasSuffix("！") || chunk.hasSuffix("？"))
        }
        #expect(chunks.joined() == text)
    }

    @Test func noSeparatorHardSplit() {
        let text = String(repeating: "啊", count: 250)
        let chunks = TranscriptChunker(maxChars: 100).chunk(text)
        #expect(chunks.count == 3)
        for chunk in chunks {
            #expect(chunk.count <= 100)
        }
        #expect(chunks.joined() == text)
    }

    @Test func newlineIsBreak() {
        let text = "第一行\n第二行\n第三行"
        let chunks = TranscriptChunker(maxChars: 8).chunk(text)
        #expect(chunks.count > 1)
        #expect(chunks.joined() == text)
    }

    @Test func midTextOversizedSentenceHardSplit() {
        // 句中超长句子（无标点）必须被硬切，块数 = 3、每块 ≤ maxChars
        let text = "短句。" + String(repeating: "长", count: 150) + "。" + "尾句。"
        let chunks = TranscriptChunker(maxChars: 100).chunk(text)
        #expect(chunks.count == 3)
        for chunk in chunks {
            #expect(chunk.count <= 100)
        }
        #expect(chunks.joined() == text)
    }

    @Test func exactMaxCharsBoundary() {
        // 恰好 maxChars 字符（末位为句号）→ 单个块
        let text = String(repeating: "字", count: 99) + "。"
        let chunks = TranscriptChunker(maxChars: 100).chunk(text)
        #expect(chunks == [text])
    }

    @Test func leadingBreakAndConsecutiveBreaks() {
        #expect(TranscriptChunker().chunk("。开头") == ["。开头"])
        #expect(TranscriptChunker().chunk("。。。") == ["。。。"])
    }
}
```

- [ ] **Step 2: 运行确认失败**

```bash
cd FlashNoteCore && swift test \
  -Xswiftc -F/Library/Developer/CommandLineTools/Library/Developer/Frameworks \
  -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/Frameworks \
  -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/usr/lib
```
Expected: 编译失败——找不到 `TranscriptChunker`。

- [ ] **Step 3: 实现分块器**

`FlashNoteCore/Sources/FlashNoteCore/AI/TranscriptChunker.swift`:

```swift
import Foundation

/// 把长转写文本切成适合 LLM 的块：优先在句子边界（。！？!?\n）切分，超长块做硬切。
///
/// 算法：在 maxChars 字符窗口内取最后一个句边界作为切点；窗口内无句边界
/// （单个句子超长，常见于稀疏标点的 ASR 输出）才硬切，保证每块 ≤ maxChars。
public struct TranscriptChunker {
    public var maxChars: Int

    public init(maxChars: Int = 4000) {
        precondition(maxChars > 0, "maxChars 必须为正数")
        self.maxChars = maxChars
    }

    private let breaks = CharacterSet(charactersIn: "。！？!?\n")

    public func chunk(_ text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        var chunks: [String] = []
        var start = text.startIndex

        while start < text.endIndex {
            let windowEnd = text.index(start, offsetBy: maxChars, limitedBy: text.endIndex) ?? text.endIndex
            let window = text[start..<windowEnd]
            // 仅把窗口内部的句边界作为切点；窗口首字符若是标点（如"。开头"），
            // 让它随下文保留，避免切出孤立的单字符块。
            if let lastBreak = findLastBreak(in: window), lastBreak > window.startIndex {
                let chunkEnd = text.index(after: lastBreak)
                chunks.append(String(text[start..<chunkEnd]))
                start = chunkEnd
            } else {
                chunks.append(String(window))
                start = windowEnd
            }
        }
        return chunks
    }

    private func findLastBreak(in range: Substring) -> String.Index? {
        range.lastIndex { char in
            guard let scalar = char.unicodeScalars.first else { return false }
            return breaks.contains(scalar)
        }
    }
}
```

- [ ] **Step 4: 运行确认通过**

```bash
cd FlashNoteCore && swift test \
  -Xswiftc -F/Library/Developer/CommandLineTools/Library/Developer/Frameworks \
  -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/Frameworks \
  -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/usr/lib
```
Expected: `TranscriptChunkerTests` 全部通过（8 个测试）。

- [ ] **Step 5: 提交**

```bash
cd .. && git add FlashNoteCore && git commit -m "feat: add transcript chunker"
```

---

### Task 8: 纪要模板（内置 + 自定义）

**Files:**
- Create: `FlashNoteCore/Sources/FlashNoteCore/AI/MinutesTemplate.swift`
- Create: `FlashNoteCore/Tests/FlashNoteCoreTests/MinutesTemplateTests.swift`

- [ ] **Step 1: 写失败测试**

`FlashNoteCore/Tests/FlashNoteCoreTests/MinutesTemplateTests.swift`:

```swift
import Testing
@testable import FlashNoteCore

struct MinutesTemplateTests {
    @Test func builtinsExist() {
        let builtins = MinutesTemplate.builtins
        #expect(builtins.count == 3)
        let names = builtins.map(\.name)
        #expect(names.contains("工作纪要"))
        #expect(names.contains("会议纪要"))
        #expect(names.contains("课程纪要"))
    }

    @Test func builtinsHaveSectionsAndPrompts() {
        for template in MinutesTemplate.builtins {
            #expect(!template.sections.isEmpty, "\(template.name) 缺少分节")
            #expect(!template.systemPrompt.isEmpty)
            #expect(template.userPromptTemplate.contains("{transcript}"))
            #expect(template.isBuiltin)
        }
    }

    @Test func customTemplateCodable() throws {
        let template = MinutesTemplate(
            id: "custom-1",
            name: "面试纪要",
            isBuiltin: false,
            sections: ["候选人评估", "结论"],
            systemPrompt: "你是面试官助手。",
            userPromptTemplate: "转写如下：\n{transcript}"
        )
        let data = try JSONEncoder().encode(template)
        let decoded = try JSONDecoder().decode(MinutesTemplate.self, from: data)
        #expect(decoded == template)
    }
}
```

- [ ] **Step 2: 运行确认失败**

```bash
cd FlashNoteCore && swift test \
  -Xswiftc -F/Library/Developer/CommandLineTools/Library/Developer/Frameworks \
  -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/Frameworks \
  -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/usr/lib
```
Expected: 编译失败——找不到 `MinutesTemplate`。

- [ ] **Step 3: 实现模板**

`FlashNoteCore/Sources/FlashNoteCore/AI/MinutesTemplate.swift`:

```swift
import Foundation

/// 纪要风格模板：决定 AI 输出的结构。内置三种 + 支持用户自定义。
public struct MinutesTemplate: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var isBuiltin: Bool
    /// 期望输出的小节标题（Markdown 二级标题），如 ["结论", "行动项", "待跟进"]。
    public var sections: [String]
    public var systemPrompt: String
    /// 用户消息模板，必须包含 {transcript} 占位符。
    public var userPromptTemplate: String

    public init(
        id: String,
        name: String,
        isBuiltin: Bool,
        sections: [String],
        systemPrompt: String,
        userPromptTemplate: String
    ) {
        self.id = id
        self.name = name
        self.isBuiltin = isBuiltin
        self.sections = sections
        self.systemPrompt = systemPrompt
        self.userPromptTemplate = userPromptTemplate
    }

    public static let builtins: [MinutesTemplate] = [.work, .meeting, .lecture]

    private static let work = MinutesTemplate(
        id: "builtin.work",
        name: "工作纪要",
        isBuiltin: true,
        sections: ["结论", "行动项", "待跟进"],
        systemPrompt: "你是专业的工作纪要助手。输出简洁的工作纪要，必须使用指定的小节标题。行动项需提炼负责人与截止时间（如原文提及）。全程使用中文。",
        userPromptTemplate: "请根据以下会议转写内容生成「工作纪要」，必须使用指定小节标题。\n\n转写内容：\n{transcript}"
    )

    private static let meeting = MinutesTemplate(
        id: "builtin.meeting",
        name: "会议纪要",
        isBuiltin: true,
        sections: ["议题", "讨论要点", "决议", "待办"],
        systemPrompt: "你是专业的会议纪要助手。输出结构清晰的会议纪要，必须使用指定的小节标题。决议与待办需明确。全程使用中文。",
        userPromptTemplate: "请根据以下会议转写内容生成「会议纪要」，必须使用指定小节标题。\n\n转写内容：\n{transcript}"
    )

    private static let lecture = MinutesTemplate(
        id: "builtin.lecture",
        name: "课程纪要",
        isBuiltin: true,
        sections: ["知识点", "重点难点", "疑问", "复习建议"],
        systemPrompt: "你是专业的课程笔记助手。输出适合复习的课程纪要，必须使用指定的小节标题。重点难点需突出。全程使用中文。",
        userPromptTemplate: "请根据以下课堂转写内容生成「课程纪要」，必须使用指定小节标题。\n\n转写内容：\n{transcript}"
    )
}
```

- [ ] **Step 4: 运行确认通过**

```bash
cd FlashNoteCore && swift test \
  -Xswiftc -F/Library/Developer/CommandLineTools/Library/Developer/Frameworks \
  -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/Frameworks \
  -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/usr/lib
```
Expected: `MinutesTemplateTests` 全部通过（3 个测试）。

- [ ] **Step 5: 提交**

```bash
cd .. && git add FlashNoteCore && git commit -m "feat: add minutes templates (builtin + custom)"
```

---

### Task 9: 纪要生成器

**Files:**
- Create: `FlashNoteCore/Sources/FlashNoteCore/AI/MinutesGenerator.swift`
- Create: `FlashNoteCore/Tests/FlashNoteCoreTests/MinutesGeneratorTests.swift`

- [ ] **Step 1: 写失败测试**

`FlashNoteCore/Tests/FlashNoteCoreTests/MinutesGeneratorTests.swift`:

```swift
import Testing
@testable import FlashNoteCore

/// 测试替身：按预设响应回复 complete；记录调用。
final class MockLLMClient: LLMClient {
    let modelName = "mock-model"
    var onComplete: (([ChatMessage]) -> String)?
    private(set) var calls: [[ChatMessage]] = []

    func complete(messages: [ChatMessage]) async throws -> String {
        calls.append(messages)
        return onComplete?(messages) ?? ""
    }

    func stream(messages: [ChatMessage]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(onComplete?(messages) ?? "")
            continuation.finish()
        }
    }
}

struct MinutesGeneratorTests {
    private let recordingID = UUID()

    @Test func shortTranscriptSingleCallAndSections() async throws {
        let client = MockLLMClient()
        client.onComplete = { messages in
            #expect(messages.count == 2) // system + user
            #expect(messages[0].role == .system)
            #expect(messages[1].content.contains("转写内容"))
            return """
            ## 结论
            通过可插拔转写架构。

            ## 行动项
            - 张伟：完成接口定义

            ## 待跟进
            下周评审。
            """
        }
        let generator = MinutesGenerator(client: client)
        let minutes = try await generator.generate(
            transcript: "这是一段很短的转写。",
            template: .builtins[0],
            recordingID: recordingID
        )
        #expect(client.calls.count == 1)
        #expect(minutes.recordingID == recordingID)
        #expect(minutes.templateID == "builtin.work")
        #expect(minutes.styleName == "工作纪要")
        #expect(minutes.model == "mock-model")
        #expect(minutes.sections.count == 3)
        #expect(minutes.sections[0].title == "结论")
        #expect(minutes.sections[0].body.contains("可插拔"))
        #expect(minutes.sections[1].title == "行动项")
    }

    @Test func customTemplateWithoutPlaceholderStillGetsTranscript() async throws {
        let client = MockLLMClient()
        client.onComplete = { messages in
            #expect(messages[1].content.contains("转写内容"))
            #expect(messages[1].content.contains("这是一段待纪要的转写"))
            #expect(messages[1].content.contains("不要新增其他小节"))
            return "## 结论\nOK。\n## 行动项\n\n## 待跟进\n"
        }
        let template = MinutesTemplate(
            id: "custom-no-placeholder",
            name: "自定义",
            isBuiltin: false,
            sections: ["结论", "行动项", "待跟进"],
            systemPrompt: "你是助手。",
            userPromptTemplate: "请生成纪要。"
        )
        let minutes = try await MinutesGenerator(client: client).generate(
            transcript: "这是一段待纪要的转写",
            template: template,
            recordingID: recordingID
        )
        #expect(minutes.sections[0].body == "OK。")
    }

    @Test func longTranscriptChunkedBeforeFinalCall() async throws {
        let client = MockLLMClient()
        client.onComplete = { messages in
            // 第一轮：片段摘要调用，system 为摘要指令
            if messages[0].content.contains("摘要") {
                return "片段要点。"
            }
            return """
            ## 结论
            结论内容。

            ## 行动项
            行动项内容。

            ## 待跟进
            待跟进内容。
            """
        }
        let longText = String(repeating: "这是很长的一段会议内容。", count: 200)
        let generator = MinutesGenerator(
            client: client,
            chunker: TranscriptChunker(maxChars: 100)
        )
        let minutes = try await generator.generate(
            transcript: longText,
            template: .builtins[0],
            recordingID: recordingID
        )
        // 分段调用 + 最终生成调用
        #expect(client.calls.count > 1)
        #expect(minutes.sections.count == 3)
    }

    @Test func missingSectionFilledEmpty() async throws {
        let client = MockLLMClient()
        client.onComplete = { _ in "## 结论\n只有结论。" }
        let generator = MinutesGenerator(client: client)
        let minutes = try await generator.generate(
            transcript: "短文本。",
            template: .builtins[0],
            recordingID: recordingID
        )
        #expect(minutes.sections.count == 3)
        #expect(minutes.sections[0].title == "结论")
        #expect(!minutes.sections[0].body.isEmpty)
        #expect(minutes.sections[1].body == "")
        #expect(minutes.sections[2].body == "")
    }

    @Test func minutesCodable() throws {
        let minutes = Minutes(
            id: UUID(),
            recordingID: recordingID,
            templateID: "builtin.work",
            styleName: "工作纪要",
            sections: [MinutesSection(title: "结论", body: "x")],
            model: "mock",
            promptVersion: "1",
            generatedAt: Date(timeIntervalSince1970: 100)
        )
        let data = try JSONEncoder().encode(minutes)
        let decoded = try JSONDecoder().decode(Minutes.self, from: data)
        #expect(decoded == minutes)
    }
}
```

- [ ] **Step 2: 运行确认失败**

```bash
cd FlashNoteCore && swift test \
  -Xswiftc -F/Library/Developer/CommandLineTools/Library/Developer/Frameworks \
  -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/Frameworks \
  -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/usr/lib
```
Expected: 编译失败——找不到 `Minutes` / `MinutesSection` / `MinutesGenerator`。

- [ ] **Step 3: 实现生成器**

`FlashNoteCore/Sources/FlashNoteCore/AI/MinutesGenerator.swift`:

```swift
import Foundation

/// 纪要的一个分节。
public struct MinutesSection: Codable, Equatable, Sendable {
    public var title: String
    public var body: String

    public init(title: String, body: String) {
        self.title = title
        self.body = body
    }
}

/// AI 生成的纪要。
public struct Minutes: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var recordingID: UUID
    public var templateID: String
    public var styleName: String
    public var sections: [MinutesSection]
    public var model: String
    public var promptVersion: String
    public var generatedAt: Date

    public init(
        id: UUID = UUID(),
        recordingID: UUID,
        templateID: String,
        styleName: String,
        sections: [MinutesSection],
        model: String,
        promptVersion: String = "1",
        generatedAt: Date = Date()
    ) {
        self.id = id
        self.recordingID = recordingID
        self.templateID = templateID
        self.styleName = styleName
        self.sections = sections
        self.model = model
        self.promptVersion = promptVersion
        self.generatedAt = generatedAt
    }
}

/// 基于模板 + LLM 生成纪要。长转写先分块摘要再最终生成，控制 token。
public struct MinutesGenerator {
    private let client: LLMClient
    private let chunker: TranscriptChunker

    public init(client: LLMClient, chunker: TranscriptChunker = TranscriptChunker()) {
        self.client = client
        self.chunker = chunker
    }

    public func generate(
        transcript: String,
        template: MinutesTemplate,
        recordingID: UUID
    ) async throws -> Minutes {
        let prepared: String
        if transcript.count > chunker.maxChars {
            prepared = try await summarizeChunks(transcript)
        } else {
            prepared = transcript
        }

        let messages = [
            ChatMessage(role: .system, content: template.systemPrompt),
            ChatMessage(role: .user, content: makeUserPrompt(template: template, transcript: prepared))
        ]
        let output = try await client.complete(messages: messages)
        let sections = Self.parseSections(output, expected: template.sections)
        return Minutes(
            recordingID: recordingID,
            templateID: template.id,
            styleName: template.name,
            sections: sections,
            model: client.modelName
        )
    }

    private func summarizeChunks(_ transcript: String) async throws -> String {
        let chunks = chunker.chunk(transcript)
        var summaries: [String] = []
        for chunk in chunks {
            let messages = [
                ChatMessage(role: .system, content: "你是会议摘要助手。用简洁的中文要点概括以下转写片段，保留人名、数字与结论。"),
                ChatMessage(role: .user, content: chunk)
            ]
            let summary = try await client.complete(messages: messages)
            summaries.append(summary)
        }
        return summaries.joined(separator: "\n")
    }

    private func makeUserPrompt(template: MinutesTemplate, transcript: String) -> String {
        var prompt = template.userPromptTemplate
        if prompt.contains("{transcript}") {
            prompt = prompt.replacingOccurrences(of: "{transcript}", with: transcript)
        } else {
            // 自定义模板缺少占位符时，直接追加转写内容，避免静默丢失输入
            prompt += "\n\n转写内容：\n\(transcript)"
        }
        let headers = template.sections.map { "## \($0)" }.joined(separator: "\n")
        // 钉死小节格式：防止模型输出 "## 结论：" / "### 结论" 变体导致分节解析静默丢失
        prompt += "\n\n必须严格使用以下小节标题（Markdown 二级标题，标题后不加冒号或编号，不要新增其他小节）：\n\(headers)"
        return prompt
    }

    /// 解析 LLM 输出的 Markdown，按 "## 标题" 提取各节；缺失的节补空。
    static func parseSections(_ output: String, expected: [String]) -> [MinutesSection] {
        var found: [MinutesSection] = []
        var currentTitle: String?
        var currentBody: [String] = []

        func flush() {
            if let title = currentTitle {
                let body = currentBody.joined(separator: "\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                found.append(MinutesSection(title: title, body: body))
            }
            currentTitle = nil
            currentBody = []
        }

        for line in output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("## ") {
                flush()
                currentTitle = String(trimmed.dropFirst(3))
            } else if currentTitle != nil {
                currentBody.append(line)
            }
        }
        flush()

        var byTitle: [String: String] = [:]
        for section in found {
            byTitle[section.title] = section.body
        }
        return expected.map { MinutesSection(title: $0, body: byTitle[$0] ?? "") }
    }
}
```

- [ ] **Step 4: 运行确认通过**

```bash
cd FlashNoteCore && swift test \
  -Xswiftc -F/Library/Developer/CommandLineTools/Library/Developer/Frameworks \
  -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/Frameworks \
  -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/usr/lib
```
Expected: `MinutesGeneratorTests` 全部通过（5 个测试）。

- [ ] **Step 5: 提交**

```bash
cd .. && git add FlashNoteCore && git commit -m "feat: add minutes generator with section parsing"
```

---

### Task 10: 文件存储层

**Files:**
- Create: `FlashNoteCore/Sources/FlashNoteCore/Store/RecordingStore.swift`
- Create: `FlashNoteCore/Sources/FlashNoteCore/Store/FileRecordingStore.swift`
- Create: `FlashNoteCore/Tests/FlashNoteCoreTests/FileRecordingStoreTests.swift`

- [ ] **Step 1: 写失败测试**

`FlashNoteCore/Tests/FlashNoteCoreTests/FileRecordingStoreTests.swift`:

```swift
import Testing
@testable import FlashNoteCore

final class FileRecordingStoreTests {
    private let root: URL
    private let store: FileRecordingStore

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlashNoteTests-\(UUID().uuidString)")
        store = try FileRecordingStore(root: root)
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    @Test func recordingCRUD() throws {
        let rec = Recording(title: "周会纪要")
        try store.upsertRecording(rec)
        #expect(try store.fetchRecordings() == [rec])
        #expect(try store.fetchRecording(id: rec.id) == rec)

        var updated = rec
        updated.markTranscribed()
        try store.upsertRecording(updated)
        #expect(try store.fetchRecording(id: rec.id)?.status == .transcribed)

        try store.deleteRecording(id: rec.id)
        #expect(try store.fetchRecording(id: rec.id) == nil)
        #expect(try store.fetchRecordings() == [])
    }

    @Test func storePersistsAcrossInstances() throws {
        let rec = Recording(title: "持久化")
        try store.upsertRecording(rec)
        let second = try FileRecordingStore(root: root)
        #expect(try second.fetchRecordings() == [rec])
    }

    @Test func transcriptAndMinutesRoundTrip() throws {
        let rec = Recording(title: "x")
        try store.upsertRecording(rec)
        var transcript = Transcript(recordingID: rec.id)
        transcript.append(TranscriptSegment(startTime: 0, text: "第一句。"))
        try store.upsertTranscript(transcript)
        #expect(try store.fetchTranscript(recordingID: rec.id) == transcript)

        let minutes = Minutes(
            recordingID: rec.id,
            templateID: "builtin.work",
            styleName: "工作纪要",
            sections: [MinutesSection(title: "结论", body: "通过。")],
            model: "mock"
        )
        try store.upsertMinutes(minutes)
        #expect(try store.fetchMinutes(recordingID: rec.id) == minutes)
    }

    @Test func folderCRUD() throws {
        let folder = Folder(name: "工作")
        try store.upsertFolder(folder)
        #expect(try store.fetchFolders() == [folder])
    }

    @Test func corruptedFileThrows() throws {
        let rec = Recording(title: "x")
        try store.upsertRecording(rec)
        try "not json".write(to: root.appendingPathComponent("recording-\(rec.id.uuidString).json"), atomically: true, encoding: .utf8)
        do {
            _ = try store.fetchRecording(id: rec.id)
            Issue.record("应当抛出错误")
        } catch {
            #expect(error as? StoreError == .corrupted("recording"))
        }
    }

    @Test func missingRecordingReturnsNil() throws {
        #expect(try store.fetchRecording(id: UUID()) == nil)
    }
}
```

- [ ] **Step 2: 运行确认失败**

```bash
cd FlashNoteCore && swift test \
  -Xswiftc -F/Library/Developer/CommandLineTools/Library/Developer/Frameworks \
  -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/Frameworks \
  -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/usr/lib
```
Expected: 编译失败——找不到 `RecordingStore` / `FileRecordingStore` / `StoreError`。

- [ ] **Step 3: 实现存储层**

`FlashNoteCore/Sources/FlashNoteCore/Store/RecordingStore.swift`:

```swift
import Foundation

public enum StoreError: Error, Equatable {
    case corrupted(String)
}

/// 数据访问抽象。App 层后续提供 CloudKit 实现，UI 无感知。
public protocol RecordingStore: AnyObject, Sendable {
    func fetchRecordings() throws -> [Recording]
    func fetchRecording(id: UUID) throws -> Recording?
    func upsertRecording(_ recording: Recording) throws
    func deleteRecording(id: UUID) throws

    func fetchTranscript(recordingID: UUID) throws -> Transcript?
    func upsertTranscript(_ transcript: Transcript) throws

    func fetchMinutes(recordingID: UUID) throws -> Minutes?
    func upsertMinutes(_ minutes: Minutes) throws

    func fetchFolders() throws -> [Folder]
    func upsertFolder(_ folder: Folder) throws
}
```

`FlashNoteCore/Sources/FlashNoteCore/Store/FileRecordingStore.swift`:

```swift
import Foundation

/// JSON 文件实现的本地存储。每个实体一个文件：{kind}-{id}.json。
public final class FileRecordingStore: RecordingStore, @unchecked Sendable {
    private let root: URL
    private let lock = NSLock()
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(root: URL) throws {
        self.root = root
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        // 不设置自定义日期策略（保持默认 deferredToDate，参考日期 Double 编码）。
        // 实测（本机 CLT Foundation）：.iso8601 与 .secondsSince1970/.millisecondsSince1970
        // 都会损坏亚秒精度，导致 Date() 生成的戳 encode→decode 后不相等；默认策略 0/50000 失败。
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder
        let decoder = JSONDecoder()
        self.decoder = decoder
    }

    private func url(kind: String, id: UUID) -> URL {
        root.appendingPathComponent("\(kind)-\(id.uuidString).json")
    }

    private func load<T: Decodable>(_ type: T.Type, kind: String, id: UUID) throws -> T? {
        let file = url(kind: kind, id: id)
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        do {
            let data = try Data(contentsOf: file)
            return try decoder.decode(T.self, from: data)
        } catch {
            throw StoreError.corrupted(kind)
        }
    }

    private func save<T: Encodable>(_ value: T, kind: String, id: UUID) throws {
        let data = try encoder.encode(value)
        try data.write(to: url(kind: kind, id: id), options: .atomic)
    }

    public func fetchRecordings() throws -> [Recording] {
        lock.lock(); defer { lock.unlock() }
        let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        var result: [Recording] = []
        for file in files where file.lastPathComponent.hasPrefix("recording-") {
            do {
                let data = try Data(contentsOf: file)
                result.append(try decoder.decode(Recording.self, from: data))
            } catch {
                throw StoreError.corrupted("recording")
            }
        }
        return result.sorted { $0.createdAt > $1.createdAt }
    }

    public func fetchRecording(id: UUID) throws -> Recording? {
        lock.lock(); defer { lock.unlock() }
        return try load(Recording.self, kind: "recording", id: id)
    }

    public func upsertRecording(_ recording: Recording) throws {
        lock.lock(); defer { lock.unlock() }
        try save(recording, kind: "recording", id: recording.id)
    }

    public func deleteRecording(id: UUID) throws {
        lock.lock(); defer { lock.unlock() }
        try FileManager.default.removeItem(at: url(kind: "recording", id: id))
    }

    public func fetchTranscript(recordingID: UUID) throws -> Transcript? {
        lock.lock(); defer { lock.unlock() }
        return try load(Transcript.self, kind: "transcript", id: recordingID)
    }

    public func upsertTranscript(_ transcript: Transcript) throws {
        lock.lock(); defer { lock.unlock() }
        try save(transcript, kind: "transcript", id: transcript.recordingID)
    }

    public func fetchMinutes(recordingID: UUID) throws -> Minutes? {
        lock.lock(); defer { lock.unlock() }
        return try load(Minutes.self, kind: "minutes", id: recordingID)
    }

    public func upsertMinutes(_ minutes: Minutes) throws {
        lock.lock(); defer { lock.unlock() }
        try save(minutes, kind: "minutes", id: minutes.recordingID)
    }

    public func fetchFolders() throws -> [Folder] {
        lock.lock(); defer { lock.unlock() }
        let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        var result: [Folder] = []
        for file in files where file.lastPathComponent.hasPrefix("folder-") {
            do {
                let data = try Data(contentsOf: file)
                result.append(try decoder.decode(Folder.self, from: data))
            } catch {
                throw StoreError.corrupted("folder")
            }
        }
        return result.sorted { $0.createdAt < $1.createdAt }
    }

    public func upsertFolder(_ folder: Folder) throws {
        lock.lock(); defer { lock.unlock() }
        try save(folder, kind: "folder", id: folder.id)
    }
}
```

注意：`deleteRecording` 对不存在的文件会抛错。测试 `testRecordingCRUD` 中先 upsert 再 delete，路径存在，不会触发该问题。

- [ ] **Step 4: 运行确认通过**

```bash
cd FlashNoteCore && swift test \
  -Xswiftc -F/Library/Developer/CommandLineTools/Library/Developer/Frameworks \
  -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/Frameworks \
  -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/usr/lib
```
Expected: `FileRecordingStoreTests` 全部通过（6 个测试）。

- [ ] **Step 5: 提交**

```bash
cd .. && git add FlashNoteCore && git commit -m "feat: add file-based recording store"
```

---

### Task 11: 端到端集成测试与 README

**Files:**
- Create: `FlashNoteCore/Tests/FlashNoteCoreTests/IntegrationTests.swift`
- Create: `FlashNoteCore/README.md`

- [ ] **Step 1: 写失败测试**

`FlashNoteCore/Tests/FlashNoteCoreTests/IntegrationTests.swift`:

```swift
import Testing
@testable import FlashNoteCore

struct IntegrationTests {
    @Test func fullPipeline() async throws {
        // 1) 录音 → 转写服务（Mock 引擎）
        let recordingID = UUID()
        let engine = MockTranscriptionEngine()
        let service = TranscriptionService(recordingID: recordingID, engine: engine)
        try service.begin()
        let transcript = service.finish()
        #expect(!transcript.fullText.isEmpty)

        // 2) 纪要生成（Mock LLM）
        let client = MockLLMClient()
        client.onComplete = { _ in
            """
            ## 结论
            通过了可插拔转写架构。

            ## 行动项
            - 张伟：完成接口定义

            ## 待跟进
            下周评审。
            """
        }
        let minutes = try await MinutesGenerator(client: client).generate(
            transcript: transcript.fullText,
            template: .builtins[0],
            recordingID: recordingID
        )
        #expect(minutes.sections.count == 3)

        // 3) 存储往返
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlashNoteIntegration-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try FileRecordingStore(root: root)
        var rec = Recording(id: recordingID, title: "周会纪要")
        rec.markTranscribed()
        rec.markSummarized()
        try store.upsertRecording(rec)
        try store.upsertTranscript(transcript)
        try store.upsertMinutes(minutes)

        let loadedRec = try store.fetchRecording(id: recordingID)
        let loadedTranscript = try store.fetchTranscript(recordingID: recordingID)
        let loadedMinutes = try store.fetchMinutes(recordingID: recordingID)
        #expect(loadedRec == rec)
        #expect(loadedTranscript == transcript)
        #expect(loadedMinutes == minutes)
    }
}
```

注意：`MockTranscriptionEngine` 与 `MockLLMClient` 定义在 `TranscriptionServiceTests.swift` / `MinutesGeneratorTests.swift` 中，同 target 内可直接复用，无需重复定义。

- [ ] **Step 2: 运行确认**

```bash
cd FlashNoteCore && swift test \
  -Xswiftc -F/Library/Developer/CommandLineTools/Library/Developer/Frameworks \
  -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/Frameworks \
  -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/usr/lib
```
Expected: 编译成功且全部测试通过。`MockTranscriptionEngine` 与 `MockLLMClient` 与 `IntegrationTests` 同属 `FlashNoteCoreTests` 测试 target，模块内互相可见，可直接复用。

- [ ] **Step 3: 兜底修正（仅在 Step 2 报"找不到 Mock 类型"时执行）**

若 Step 2 编译失败提示找不到 `MockTranscriptionEngine` 或 `MockLLMClient`，把两个 Mock 类定义移到 `IntegrationTests.swift` 顶部，并删除 `TranscriptionServiceTests.swift` 与 `MinutesGeneratorTests.swift` 中的重复定义：

```swift
import Testing
@testable import FlashNoteCore

final class MockTranscriptionEngine: TranscriptionEngine {
    let displayName = "MockEngine"
    let isRealtime = true
    var onSegment: ((TranscriptSegment) -> Void)?
    var onError: ((Error) -> Void)?
    private(set) var started = false
    private(set) var cancelled = false
    func start() throws {
        started = true
        onSegment?(TranscriptSegment(startTime: 0, text: "你好。"))
        onSegment?(TranscriptSegment(startTime: 2, text: "这是一段测试转写。"))
    }
    func cancel() { cancelled = true }
}

final class MockLLMClient: LLMClient {
    let modelName = "mock-model"
    var onComplete: (([ChatMessage]) -> String)?
    private(set) var calls: [[ChatMessage]] = []
    func complete(messages: [ChatMessage]) async throws -> String {
        calls.append(messages)
        return onComplete?(messages) ?? ""
    }
    func stream(messages: [ChatMessage]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(onComplete?(messages) ?? "")
            continuation.finish()
        }
    }
}

struct IntegrationTests {
    // ...（Task 11 Step 1 的测试体）
}
```

然后删除 `TranscriptionServiceTests.swift` 与 `MinutesGeneratorTests.swift` 中重复的 Mock 定义。

```bash
cd FlashNoteCore && swift test \
  -Xswiftc -F/Library/Developer/CommandLineTools/Library/Developer/Frameworks \
  -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/Frameworks \
  -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/usr/lib
```
Expected: 全部测试通过（含集成测试）。

- [ ] **Step 4: 编写 README**

`FlashNoteCore/README.md`:

```markdown
# FlashNoteCore

FlashNote 的核心领域层（纯 Swift，无平台依赖）。

## 模块

- **Models** — Recording / Transcript / Folder
- **Transcription** — `TranscriptionEngine` 协议（可插拔转写通道）+ `TranscriptionService`
- **AI** — OpenAI 兼容 `LLMClient`、`TranscriptChunker`、`MinutesTemplate`（内置工作/会议/课程）+ `MinutesGenerator`
- **Store** — `RecordingStore` 协议 + JSON 文件实现

## 构建与测试

```bash
cd FlashNoteCore
swift build
swift test \
  -Xswiftc -F/Library/Developer/CommandLineTools/Library/Developer/Frameworks \
  -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/Frameworks \
  -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/usr/lib
```

## 接入说明

App 层需提供：
1. `TranscriptionEngine` 实现（Apple Speech / Whisper / 云端 ASR）；
2. `LLMClient` 可复用 `OpenAICompatibleClient`（填入用户配置的 Base URL + Key + 模型）；
3. `RecordingStore` 可复用 `FileRecordingStore` 或实现 CloudKit 版本。
```

- [ ] **Step 5: 全量测试 + 提交**

```bash
cd FlashNoteCore && swift test \
  -Xswiftc -F/Library/Developer/CommandLineTools/Library/Developer/Frameworks \
  -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/Frameworks \
  -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/usr/lib && cd ..
git add FlashNoteCore && git commit -m "feat: end-to-end integration test and README"
```

Expected: 全量测试通过，提交成功。

---

## 自检结果（计划作者已执行）

**1. Spec 覆盖：**
- 模型（Recording/Transcript/Folder/Minutes/Template）→ Task 2-4, 8, 9 ✓
- 转写可插拔架构（`TranscriptionEngine` 协议）→ Task 5 ✓
- LLM 层 OpenAI 兼容（Base URL + Key + 模型）→ Task 6 ✓
- 纪要风格（内置三风格 + 自定义模板）→ Task 8 ✓
- 纪要生成 + 长文本分段 → Task 7, 9 ✓
- 存储抽象（后续 CloudKit 替换）→ Task 10 ✓
- UI / 录音 / 系统转写 / CloudKit / 搜索 / 打包 → 明确标记为后续计划（需 Xcode）✓

**2. 占位符扫描：** 无 TBD/TODO；每个代码步骤含完整代码。

**3. 类型一致性：** `TranscriptSegment(startTime:text:)` 依赖 Task 3 的默认参数；`Minutes(templateID:styleName:sections:model:)` 依赖 Task 9 的默认参数；`MinutesTemplate.builtins[0]` 为工作纪要；`StoreError.corrupted` 在 Task 10 定义；Mock 类型在 Task 5/9 定义并在 Task 11 复用（含可见性修正步骤）。

**4. 已知取舍：**
- `FileRecordingStore.deleteRecording` 对不存在文件抛错（测试未覆盖该路径，符合当前需求）。
- `fetchRecordings` 依赖 `contentsOfDirectory`，子目录中其他文件被忽略（前缀过滤）。
- 测试使用 Swift Testing 而非 XCTest：CLT-only 机器（无 Xcode）的 macOS SDK 不含 XCTest.framework，Swift Testing 随 Swift 工具链一起提供。
- 本机 `swift test` 需携带文档中的框架路径与 rpath 标志（`-F/path` 必须使用紧贴形式）；装有 Xcode 的机器上直接运行 `swift test` 即可，无需标志。
