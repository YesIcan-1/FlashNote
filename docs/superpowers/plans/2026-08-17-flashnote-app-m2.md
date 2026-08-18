# FlashNote App M2 实施计划（导入音频 + 双引擎转写 + 播放器）

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 M1（录音 + 实时转写）基础上，实现「导入音频文件 → 转写（云端 Whisper API / 本地 WhisperKit 双引擎可切换）→ 全文转写展示 → 音频播放」，并新增设置页配置转写引擎与 LLM 连接。

**Architecture:** 核心层新增 `AudioTranscriptionClient` 协议 + `OpenAIWhisperClient`（OpenAI `/audio/transcriptions` 多段上传、verbose_json 解析为 `[TranscriptSegment]`，URLProtocol 桩测试）；App 层新增 `FileTranscriptionEngine` 协议（整段文件转写抽象）+ 两个实现 `CloudWhisperEngine`（复用核心客户端）与 `WhisperKitEngine`（本地）；`ImportTranscriptionViewModel` 编排导入→引擎选择→转写→保存；`AudioPlayer` 用 AVPlayer 播放。

**Tech Stack:** SwiftUI、AVFoundation（AVPlayer / AVAudioFile）、URLSession（multipart）、WhisperKit（远程 Swift 包）、核心层 FlashNoteCore、Swift Testing。

**环境约束（沿用 M1 实测结论）：**
- 构建命令必须带 `ONLY_ACTIVE_ARCH=YES ARCHS=arm64`（macOS 测试与 iOS 构建）。
- 测试用 macOS 测试 target（`FlashNoteMacTests`）；iOS 构建用 `-sdk iphoneos CODE_SIGNING_ALLOWED=NO`。
- 手动验证必须用 `open` 启动（TCC 责任归属）。
- 测试文件用平台条件导入（`@testable import FlashNoteMac` / `FlashNote`）。
- **WhisperKit 是远程包**：需验证 XcodeGen 2.46 + Xcode 26.6 下远程包引用是否正常（M1 只踩了本地包路径解析坑，远程包应不受影响；Task 4 前置验证，若异常则 M2 先交付云端引擎，本地 Whisper 顺延）。

---

## 文件结构

```
FlashNoteCore/Sources/FlashNoteCore/AI/
├── AudioTranscriptionClient.swift   # 协议 + OpenAIWhisperClient（multipart + verbose_json）
FlashNoteCore/Tests/FlashNoteCoreTests/
├── OpenAIWhisperClientTests.swift
App/
├── AppSettings.swift                # 引擎偏好 + LLM 配置（UserDefaults + Keychain）
Services/Transcription/
├── FileTranscriptionEngine.swift    # App 层整段转写协议
├── CloudWhisperEngine.swift         # 云端 Whisper API 实现
└── WhisperKitEngine.swift           # 本地 WhisperKit 实现
Features/Import/
├── ImportTranscriptionViewModel.swift  # 编排（可单测）
└── ImportAudioView.swift            # 导入 + 转写进度 + 引擎选择
Features/Detail/
├── AudioPlayer.swift                # AVPlayer 封装
└── (RecordingDetailView 播放 tab 接入)
Features/Settings/
└── SettingsView.swift               # 设置页（引擎/LLM/模型下载）
Tests/
├── ImportTranscriptionViewModelTests.swift
└── Support/ 复用 InMemoryStore + Mock 引擎
```

**本计划之外（后续里程碑）：** M3 AI 纪要 UI（复用设置页 LLM 配置）；M4 iCloud 同步/文件夹/搜索；M5 打磨发布。说话人自动分离（分人转写）在 M2+ 单独做（数据已带时间戳，见 M1 分句）。

---

### Task 1: 核心层 AudioTranscriptionClient（OpenAI Whisper）

**Files:**
- Create: `FlashNoteCore/Sources/FlashNoteCore/AI/AudioTranscriptionClient.swift`
- Create: `FlashNoteCore/Tests/FlashNoteCoreTests/OpenAIWhisperClientTests.swift`

- [ ] **Step 1: 写失败测试**（核心包，`cd FlashNoteCore && swift test`）

`OpenAIWhisperClientTests.swift`（Swift Testing + MockURLProtocol 桩——核心包已有 URLProtocol 测试先例）：

```swift
import Testing
import Foundation
@testable import FlashNoteCore

final class WhisperURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let handler = WhisperURLProtocol.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL)); return
        }
        do {
            let (resp, data) = try handler(request)
            client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

@Suite(.serialized)
struct OpenAIWhisperClientTests {
    private func session() -> URLSession {
        let c = URLSessionConfiguration.ephemeral
        c.protocolClasses = [WhisperURLProtocol.self]
        return URLSession(configuration: c)
    }

    @Test func transcribeParsesVerboseJsonSegments() async throws {
        let json = """
        {"text":"第一句。第二句。","segments":[
          {"id":0,"start":0.0,"end":1.5,"text":"第一句。","tokens":[]},
          {"id":1,"start":1.6,"end":3.0,"text":"第二句。","tokens":[]}
        ]}
        """
        WhisperURLProtocol.handler = { req in
            #expect(req.url?.path == "/audio/transcriptions")
            #expect(req.httpMethod == "POST")
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (resp, json.data(using: .utf8)!)
        }
        let client = OpenAIWhisperClient(
            baseURL: URL(string: "https://api.openai.com/v1")!,
            apiKey: "k", model: "whisper-1", session: session()
        )
        let segments = try await client.transcribe(audioData: Data([1,2,3]), filename: "a.m4a", language: "zh")
        #expect(segments.count == 2)
        #expect(segments[0].text == "第一句。")
        #expect(abs(segments[0].startTime - 0.0) < 0.001)
        #expect(abs(segments[1].endTime! - 3.0) < 0.001)
    }

    @Test func transcribeThrowsOnHTTPError() async {
        WhisperURLProtocol.handler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (resp, Data())
        }
        let client = OpenAIWhisperClient(baseURL: URL(string: "https://api.openai.com/v1")!, apiKey: "k", model: "whisper-1", session: session())
        await #expect(throws: LLMError.self) {
            _ = try await client.transcribe(audioData: Data(), filename: "a.m4a", language: "zh")
        }
    }
}
```

- [ ] **Step 2: 运行确认失败**

```bash
cd FlashNoteCore && swift test
```
Expected: 编译失败——找不到 `OpenAIWhisperClient`。

- [ ] **Step 3: 实现**

`AudioTranscriptionClient.swift`:

```swift
import Foundation

/// 整段音频转写客户端抽象（导入音频用）。
public protocol AudioTranscriptionClient: Sendable {
    /// 上传音频并返回分句段落（带起止时间戳）。
    func transcribe(audioData: Data, filename: String, language: String) async throws -> [TranscriptSegment]
}

/// OpenAI 兼容 `/audio/transcriptions` 客户端（Whisper API）。
public final class OpenAIWhisperClient: AudioTranscriptionClient, @unchecked Sendable {
    private let baseURL: URL
    private let apiKey: String
    private let model: String
    private let session: URLSession

    public init(baseURL: URL, apiKey: String, model: String = "whisper-1", session: URLSession = .shared) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.model = model
        self.session = session
    }

    public func transcribe(audioData: Data, filename: String, language: String) async throws -> [TranscriptSegment] {
        let url = baseURL.appendingPathComponent("audio/transcriptions")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let boundary = "FlashNote-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        var body = Data()
        func append(_ string: String) { body.append(string.data(using: .utf8)!) }
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"model\"\r\n\r\n\(model)\r\n")
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"language\"\r\n\r\n\(language)\r\n")
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"response_format\"\r\n\r\nverbose_json\r\n")
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n")
        append("Content-Type: application/octet-stream\r\n\r\n")
        body.append(audioData)
        append("\r\n--\(boundary)--\r\n")
        request.httpBody = body

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw LLMError.httpStatus(http.statusCode)
        }
        return try Self.parseVerboseJSON(data)
    }

    static func parseVerboseJSON(_ data: Data) throws -> [TranscriptSegment] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let segments = json["segments"] as? [[String: Any]] else {
            throw LLMError.invalidResponse
        }
        return segments.compactMap { dict in
            guard let text = dict["text"] as? String, !text.isEmpty else { return nil }
            let start = (dict["start"] as? NSNumber)?.doubleValue ?? 0
            let end = (dict["end"] as? NSNumber)?.doubleValue
            return TranscriptSegment(startTime: start, endTime: end, text: text.trimmingCharacters(in: .whitespacesAndNewlines), isFinal: true)
        }
    }
}
```

- [ ] **Step 4: 运行确认通过**

```bash
cd FlashNoteCore && swift test
```
Expected: 全部通过（46 个核心测试 + 2 个新测试）。

- [ ] **Step 5: 提交**

```bash
cd .. && git add FlashNoteCore && git commit -m "feat: add OpenAI Whisper audio transcription client"
```

---

### Task 2: AppSettings（引擎偏好 + LLM 配置）

**Files:**
- Create: `App/AppSettings.swift`
- Create: `Tests/AppSettingsTests.swift`

- [ ] **Step 1: 写失败测试**

`AppSettingsTests.swift`:

```swift
import Testing
import Foundation
#if os(macOS)
@testable import FlashNoteMac
#else
@testable import FlashNote
#endif

struct AppSettingsTests {
    @Test func defaultEngineIsCloud() {
        let s = AppSettings(storeDirectory: URL(fileURLWithPath: "/tmp"), keychain: MockKeychain())
        #expect(s.transcriptionEngine == .cloudWhisper)
    }

    @Test func engineRoundTrips() {
        let s = AppSettings(storeDirectory: URL(fileURLWithPath: "/tmp"), keychain: MockKeychain())
        s.transcriptionEngine = .whisperKit
        #expect(s.transcriptionEngine == .whisperKit)
    }

    @Test func llmConfigPersists() {
        let s = AppSettings(storeDirectory: URL(fileURLWithPath: "/tmp"), keychain: MockKeychain())
        s.llmBaseURL = "https://api.deepseek.com"
        s.llmModel = "deepseek-chat"
        s.llmAPIKey = "secret"
        #expect(s.llmBaseURL == "https://api.deepseek.com")
        #expect(s.llmAPIKey == "secret")
    }
}

final class MockKeychain: APIKeyStoring {
    var storage: [String: String] = [:]
    func get(_ key: String) -> String? { storage[key] }
    func set(_ value: String, for key: String) { storage[key] = value }
    func delete(_ key: String) { storage[key] = nil }
}
```

- [ ] **Step 2: 运行确认失败**

```bash
xcodegen generate
xcodebuild -project FlashNote.xcodeproj -scheme FlashNoteMac -destination 'platform=macOS' ONLY_ACTIVE_ARCH=YES ARCHS=arm64 test 2>&1 | tail -5
```
Expected: 编译失败——找不到 `AppSettings` / `APIKeyStoring`。

- [ ] **Step 3: 实现**

`App/AppSettings.swift`:

```swift
import Foundation

/// 转写引擎选择。
enum TranscriptionEngineChoice: String, CaseIterable, Identifiable {
    case cloudWhisper
    case whisperKit
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .cloudWhisper: "云端 Whisper API"
        case .whisperKit: "本地 WhisperKit"
        }
    }
}

/// API Key 存储抽象（Keychain 实现 / 测试内存实现）。
protocol APIKeyStoring {
    func get(_ key: String) -> String?
    func set(_ value: String, for key: String)
    func delete(_ key: String)
}

/// Keychain 实现。
final class KeychainAPIKeyStore: APIKeyStoring {
    func get(_ key: String) -> String? {
        var query = Self.query(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    func set(_ value: String, for key: String) {
        let data = Data(value.utf8)
        var query = Self.query(for: key)
        let update = [kSecValueData as String: data]
        if SecItemUpdate(query as CFDictionary, update as CFDictionary) != errSecSuccess {
            query[kSecValueData as String] = data
            SecItemAdd(query as CFDictionary, nil)
        }
    }
    func delete(_ key: String) {
        SecItemDelete(Self.query(for: key) as CFDictionary)
    }
    private static func query(for key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.flashnote.app",
         kSecAttrAccount as String: key]
    }
}

/// 应用设置：转写引擎偏好 + LLM 连接（apiKey 存 Keychain）。
@Observable
final class AppSettings {
    private let keychain: APIKeyStoring
    private let defaults: UserDefaults

    var transcriptionEngine: TranscriptionEngineChoice {
        get { TranscriptionEngineChoice(rawValue: defaults.string(forKey: "transcriptionEngine") ?? "") ?? .cloudWhisper }
        set { defaults.set(newValue.rawValue, forKey: "transcriptionEngine") }
    }

    var llmBaseURL: String {
        get { defaults.string(forKey: "llmBaseURL") ?? "https://api.deepseek.com" }
        set { defaults.set(newValue, forKey: "llmBaseURL") }
    }

    var llmModel: String {
        get { defaults.string(forKey: "llmModel") ?? "deepseek-chat" }
        set { defaults.set(newValue, forKey: "llmModel") }
    }

    var llmAPIKey: String {
        get { keychain.get("llmAPIKey") ?? "" }
        set { keychain.set(newValue, for: "llmAPIKey") }
    }

    init(storeDirectory: URL, keychain: APIKeyStoring = KeychainAPIKeyStore(), defaults: UserDefaults = .standard) {
        self.keychain = keychain
        self.defaults = defaults
    }
}
```

注意：需要 `import Security`（Keychain API）。`storeDirectory` 参数当前未使用（为后续音频目录配置预留），测试传入占位。

- [ ] **Step 4: 运行确认通过**（同上命令，全部测试通过）

- [ ] **Step 5: 提交**

```bash
git add App Tests && git commit -m "feat: add AppSettings (engine choice + LLM config)"
```

---

### Task 3: 云端转写引擎（App 层）

**Files:**
- Create: `Services/Transcription/FileTranscriptionEngine.swift`
- Create: `Services/Transcription/CloudWhisperEngine.swift`
- Create: `Tests/CloudWhisperEngineTests.swift`

- [ ] **Step 1: 写失败测试**

`CloudWhisperEngineTests.swift`:

```swift
import Testing
import Foundation
import FlashNoteCore
#if os(macOS)
@testable import FlashNoteMac
#else
@testable import FlashNote
#endif

struct CloudWhisperEngineTests {
    @Test func engineIsAvailableWhenKeyPresent() {
        let settings = AppSettings(storeDirectory: URL(fileURLWithPath: "/tmp"), keychain: MockKeychain())
        settings.llmAPIKey = "k"
        #expect(CloudWhisperEngine(settings: settings).isAvailable)
    }

    @Test func engineUnavailableWithoutKey() {
        let settings = AppSettings(storeDirectory: URL(fileURLWithPath: "/tmp"), keychain: MockKeychain())
        #expect(!CloudWhisperEngine(settings: settings).isAvailable)
    }
}
```

- [ ] **Step 2: 运行确认失败**

- [ ] **Step 3: 实现**

`FileTranscriptionEngine.swift`:

```swift
import Foundation
import FlashNoteCore

/// App 层整段（文件）转写引擎抽象。
protocol FileTranscriptionEngine {
    var displayName: String { get }
    var isAvailable: Bool { get }
    /// 转写音频文件，返回分句段落（带时间戳）。
    func transcribe(audioFileURL: URL, language: String) async throws -> [TranscriptSegment]
}
```

`CloudWhisperEngine.swift`:

```swift
import Foundation
import FlashNoteCore

/// 云端 Whisper API 转写引擎（复用核心 OpenAIWhisperClient）。
final class CloudWhisperEngine: FileTranscriptionEngine {
    let displayName = "云端 Whisper API"
    private let settings: AppSettings

    init(settings: AppSettings) {
        self.settings = settings
    }

    var isAvailable: Bool {
        !settings.llmAPIKey.isEmpty && URL(string: settings.llmBaseURL) != nil
    }

    func transcribe(audioFileURL: URL, language: String) async throws -> [TranscriptSegment] {
        let data = try Data(contentsOf: audioFileURL)
        let client = OpenAIWhisperClient(
            baseURL: URL(string: settings.llmBaseURL)!,
            apiKey: settings.llmAPIKey,
            model: "whisper-1"
        )
        return try await client.transcribe(audioData: data, filename: audioFileURL.lastPathComponent, language: language)
    }
}
```

- [ ] **Step 4: 运行确认通过**

- [ ] **Step 5: 提交**

```bash
git add Services Tests && git commit -m "feat: add cloud Whisper transcription engine"
```

---

### Task 4: WhisperKit 本地引擎（含远程包验证）

**Files:**
- Modify: `project.yml`（加远程包 WhisperKit + 依赖）
- Create: `Services/Transcription/WhisperKitEngine.swift`

- [ ] **Step 1: 验证远程包引用**（前置，若失败则本任务顺延、先交付云端引擎）

`project.yml` 增加：

```yaml
packages:
  WhisperKit:
    url: https://github.com/argmaxinc/WhisperKit
    from: "0.10.0"
```

macOS App target 增加依赖 `- package: WhisperKit`（iOS 同）。然后 `xcodegen generate && xcodebuild ... build`，观察远程包是否正常解析构建。若报错，记录并回退，M2 先交付云端引擎。

- [ ] **Step 2: 实现 WhisperKitEngine**

```swift
import Foundation
import FlashNoteCore
import WhisperKit

/// 本地 WhisperKit 引擎（离线）。
final class WhisperKitEngine: FileTranscriptionEngine {
    let displayName = "本地 WhisperKit"
    private var whisper: WhisperKit?

    var isAvailable: Bool { whisper != nil }

    func prepare() async throws {
        guard whisper == nil else { return }
        let config = WhisperKitConfig(model: "large-v3-turbo")  // 或默认
        whisper = try await WhisperKit(config)
    }

    func transcribe(audioFileURL: URL, language: String) async throws -> [TranscriptSegment] {
        try await prepare()
        guard let whisper else { throw TranscriptionError.engineUnavailable }
        let result = try await whisper.transcribe(audioPath: audioFileURL.path)
        return result?.segments.map { seg in
            TranscriptSegment(startTime: seg.start, endTime: seg.end, text: seg.text.trimmingCharacters(in: .whitespacesAndNewlines), isFinal: true)
        } ?? []
    }
}
```

注意：WhisperKit 的 API 名以实际版本为准（`WhisperKit(config:)` / `transcribe(audioPath:)` / `result.segments`），Step 2 需按实际 SDK 微调。模型首次运行自动下载（几百 MB）。

- [ ] **Step 3: 构建验证双平台**

```bash
xcodebuild -project FlashNote.xcodeproj -scheme FlashNoteMac -destination 'platform=macOS' ONLY_ACTIVE_ARCH=YES ARCHS=arm64 build
xcodebuild -project FlashNote.xcodeproj -scheme FlashNote -sdk iphoneos CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=YES ARCHS=arm64 build
```

- [ ] **Step 4: 提交**

```bash
git add project.yml Services && git commit -m "feat: add WhisperKit local transcription engine"
```

---

### Task 5: 导入转写编排（ImportTranscriptionViewModel）

**Files:**
- Create: `Features/Import/ImportTranscriptionViewModel.swift`
- Create: `Tests/ImportTranscriptionViewModelTests.swift`

- [ ] **Step 1: 写失败测试**

```swift
import Testing
import Foundation
import FlashNoteCore
#if os(macOS)
@testable import FlashNoteMac
#else
@testable import FlashNote
#endif

final class MockFileEngine: FileTranscriptionEngine {
    let displayName = "Mock"
    var isAvailable = true
    var segments: [TranscriptSegment] = [TranscriptSegment(startTime: 0, endTime: 1, text: "第一句。", isFinal: true)]
    func transcribe(audioFileURL: URL, language: String) async throws -> [TranscriptSegment] { segments }
}

struct ImportTranscriptionViewModelTests {
    @Test func importAndTranscribeSavesRecording() async throws {
        let store = InMemoryStore()
        let engine = MockFileEngine()
        let vm = ImportTranscriptionViewModel(store: store, engine: engine)
        let sourceURL = FileManager.default.temporaryDirectory.appendingPathComponent("src.m4a")
        try Data([1,2,3]).write(to: sourceURL)
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        try await vm.importAndTranscribe(sourceURL: sourceURL, title: "测试录音")
        #expect(vm.recordings().count == 1)
        let rec = try #require(vm.recordings().first)
        #expect(rec.status == .transcribed)
        let transcript = try store.fetchTranscript(recordingID: rec.id)
        #expect(transcript?.segments.count == 1)
        #expect(transcript?.fullText == "第一句。")
    }

    @Test func transcribeFailureKeepsRecordingAsRecording() async throws {
        let store = InMemoryStore()
        let engine = MockFileEngine()
        let vm = ImportTranscriptionViewModel(store: store, engine: engine)
        vm.shouldFail = true
        let sourceURL = FileManager.default.temporaryDirectory.appendingPathComponent("src.m4a")
        try Data([1]).write(to: sourceURL)
        defer { try? FileManager.default.removeItem(at: sourceURL) }
        do {
            try await vm.importAndTranscribe(sourceURL: sourceURL, title: "x")
            Issue.record("应当抛错")
        } catch { /* 预期 */ }
        #expect(vm.recordings().count == 1)
        #expect(vm.recordings().first?.status == .recording)
    }
}
```

- [ ] **Step 2: 运行确认失败**

- [ ] **Step 3: 实现**

```swift
import Foundation
import FlashNoteCore

/// 导入 + 转写编排：拷贝文件到容器 → 建 Recording → 转写 → 保存 Transcript。
@Observable
final class ImportTranscriptionViewModel {
    private let store: RecordingStore
    private let engine: FileTranscriptionEngine
    private let settings: AppSettings
    private let storeDirectory: URL
    private var cachedRecordings: [Recording] = []
    var shouldFail = false  // 测试用

    init(store: RecordingStore, engine: FileTranscriptionEngine, settings: AppSettings = AppSettings(storeDirectory: URL(fileURLWithPath: "/tmp"), keychain: KeychainAPIKeyStore()), storeDirectory: URL = AppEnvironment.defaultStoreDirectory()) {
        self.store = store
        self.engine = engine
        self.settings = settings
        self.storeDirectory = storeDirectory
    }

    func recordings() -> [Recording] { cachedRecordings }

    func importAndTranscribe(sourceURL: URL, title: String) async throws {
        let id = UUID()
        let audioDir = storeDirectory.appendingPathComponent("audio", isDirectory: true)
        try FileManager.default.createDirectory(at: audioDir, withIntermediateDirectories: true)
        let destURL = audioDir.appendingPathComponent("\(id.uuidString).\(sourceURL.pathExtension)")
        try FileManager.default.copyItem(at: sourceURL, to: destURL)

        var recording = Recording(id: id, title: title.isEmpty ? sourceURL.lastPathComponent : title)
        recording.audioFilename = destURL.lastPathComponent
        try store.upsertRecording(recording)

        if shouldFail {
            throw TranscriptionError.engineFailed("mock failure")
        }

        let segments = try await engine.transcribe(audioFileURL: destURL, language: "zh")
        let transcript = Transcript(recordingID: id, segments: segments, language: "zh")
        try store.upsertTranscript(transcript)
        recording.markTranscribed()
        try store.upsertRecording(recording)
        cachedRecordings = (try? store.fetchRecordings()) ?? []
    }
}
```

- [ ] **Step 4: 运行确认通过**

- [ ] **Step 5: 提交**

```bash
git add Features Tests && git commit -m "feat: add import + transcription orchestration"
```

---

### Task 6: 音频播放器

**Files:**
- Create: `Features/Detail/AudioPlayer.swift`
- Create: `Tests/AudioPlayerTests.swift`

- [ ] **Step 1: 写失败测试**

```swift
import Testing
import Foundation
import AVFoundation
#if os(macOS)
@testable import FlashNoteMac
#else
@testable import FlashNote
#endif

struct AudioPlayerTests {
    @Test func formatTime() {
        #expect(AudioPlayer.formatTime(0) == "00:00")
        #expect(AudioPlayer.formatTime(65) == "01:05")
        #expect(AudioPlayer.formatTime(3725) == "01:02:05")
    }
}
```

- [ ] **Step 2: 运行确认失败**

- [ ] **Step 3: 实现**

`AudioPlayer.swift`:

```swift
import AVFoundation
import Combine

/// 音频播放器（AVPlayer 封装）。
@Observable
final class AudioPlayer {
    private let player = AVPlayer()
    private(set) var isPlaying = false
    private(set) var duration: TimeInterval = 0
    private(set) var currentTime: TimeInterval = 0
    private var timeObserver: Any?

    func load(url: URL) {
        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)
        if let dur = item.asset.duration.seconds.isFinite ? item.asset.duration.seconds : nil {
            duration = dur
        }
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] time in
            self?.currentTime = time.seconds
        }
    }

    func play() {
        player.play()
        isPlaying = true
    }

    func pause() {
        player.pause()
        isPlaying = false
    }

    func stop() {
        player.pause()
        player.seek(to: .zero)
        isPlaying = false
        currentTime = 0
    }

    deinit {
        if let timeObserver { player.removeTimeObserver(timeObserver) }
    }

    static func formatTime(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        if total >= 3600 {
            return String(format: "%02d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
        }
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
```

- [ ] **Step 4: 运行确认通过**

- [ ] **Step 5: 提交**

```bash
git add Features Tests && git commit -m "feat: add audio player"
```

---

### Task 7: 导入 UI + 设置页 + 播放 tab 接入

**Files:**
- Create: `Features/Import/ImportAudioView.swift`
- Create: `Features/Settings/SettingsView.swift`
- Modify: `Features/Detail/RecordingDetailView.swift`（播放 tab 接入 AudioPlayer）
- Modify: `Features/Recordings/RecordingListView.swift`（导入按钮）
- Modify: `App/RootView.swift`（设置 tab 接入真实 SettingsView）

- [ ] **Step 1-5: 实现各视图**（UI 代码略，按 mockup：导入 sheet 含 fileImporter + 引擎选择 + 转写进度；设置页含引擎 Picker + LLM 配置字段 + 本地模型状态；播放 tab 用 AudioPlayer 控制条 + 进度）

关键点：
- `RecordingListView` 增加"导入音频"按钮 → `fileImporter` → `ImportAudioView`。
- 播放 tab：从 AppEnvironment.storeDirectory 拼音频 URL（`audio/{audioFilename}`）加载到 AudioPlayer。
- 设置页在 iOS 作为第三个 tab、macOS 作为侧边栏/工具栏入口。

- [ ] **Step 6: 构建验证双平台 + 提交**

```bash
xcodebuild -project FlashNote.xcodeproj -scheme FlashNoteMac -destination 'platform=macOS' ONLY_ACTIVE_ARCH=YES ARCHS=arm64 build
xcodebuild -project FlashNote.xcodeproj -scheme FlashNote -sdk iphoneos CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=YES ARCHS=arm64 build
git add Features App && git commit -m "feat: import UI, settings, and playback tab"
```

---

### Task 8: 端到端验证 + README + 合并

- [ ] **Step 1: 全量测试 + 双平台构建**
- [ ] **Step 2: macOS 手动验证清单**（open 启动）：导入一段 m4a → 选引擎转写 → 列表出现"已转写" → 详情全文分句展示 → 播放 tab 能播；设置页改引擎/填 Key 生效。
- [ ] **Step 3: 更新 README（M2 完成说明）**
- [ ] **Step 4: 提交 + 合并到 main**

---

## 自检结果

**Spec 覆盖（对照设计规格 §2/§3/§5.2/§5.3）：**
- 导入音频（UTType audio）→ Task 5/7 ✓
- 云端 ASR（用户自配 Key）→ Task 1/3 ✓
- 本地 Whisper（whisper.cpp/WhisperKit）→ Task 4 ✓
- 全文转写（分句 + 时间戳）→ Task 3/5 + M1 分句 ✓
- 播放 → Task 6/7 ✓
- 设置（转写通道选择 + LLM 配置）→ Task 2/7 ✓

**占位符扫描：** 无 TBD；每步骤含完整代码（UI 任务以 mockup 为依据、关键行为已在前序任务测试）。

**类型一致性：** `TranscriptSegment(startTime:endTime:text:isFinal:)`、`Recording(id:title:)/audioFilename/duration/markTranscribed`、`Transcript(recordingID:segments:language:)`、`LLMError.httpStatus/invalidResponse` 均来自核心包；`FileTranscriptionEngine` 在 Task 3 定义并在 Task 5 复用；`MockKeychain`/`MockFileEngine`/`InMemoryStore` 为测试替身。

**风险与取舍：**
- WhisperKit 远程包 + 模型下载是最大不确定性（Task 4 前置验证）；若受阻，M2 先交付云端引擎，本地顺延。
- WhisperKit 具体 API 名以实际 SDK 为准（Task 4 Step 2 按需微调）。
- `AppSettings` 的 `storeDirectory` 参数当前未用（预留）；Keychain 用 Security 框架。
- 说话人自动分离不在本计划（数据已带时间戳，M2+ 单独立项）。
