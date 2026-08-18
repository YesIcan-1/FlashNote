# FlashNote App M1 实施计划（工程骨架 + 录音 + 实时转写）

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 构建 FlashNote 双平台（iOS 17 / macOS 14）SwiftUI 应用骨架，实现「直接录音 + Apple Speech 实时转写 + 本地保存 + 录音列表/详情」，将已完成的 `FlashNoteCore` 核心层接入真实 App。

**Architecture:** XcodeGen 生成双 target 工程（iOS App + macOS App 共享 Sources，条件编译入口）；`AudioService`（AVAudioEngine 采集：写文件 + 电平回调 + 缓冲泵出）与 `SpeechEngine`（实现核心 `TranscriptionEngine` 协议，另暴露 App 层专属 `onPartialText` 直播通道）解耦；`RecorderViewModel` 编排录音/转写/保存三件事（依赖协议注入，可单测）；`FileRecordingStore` 直接复用核心层。

**Tech Stack:** SwiftUI（iOS 17/macOS 14，@Observable）、XcodeGen 2.46、AVFoundation（AVAudioEngine/AVAudioFile）、Speech（SFSpeechRecognizer）、本地包 FlashNoteCore、Swift Testing。

**环境前置（已就绪）：** Xcode 26.6 已激活（`xcode-select -p` = `/Applications/Xcode.app/Contents/Developer`）；iOS 26.5 模拟器运行时已装（iPhone 17 Pro）；核心包 45 测试在纯 `swift test` 下通过；`xcodegen` 位于 `/usr/local/bin/xcodegen`。**所有 `swift test` / `xcodebuild` 现在无需任何额外 flags。**

**模拟器无麦克风**：iOS 目标的单测与构建在模拟器完成；**实时录音+转写的真机验证在 macOS target 上进行**（本机有麦克风与 Speech 框架）。

## 环境实测修正（执行期间发现，后续任务必须遵守）

1. **构建命令**：本机（Apple Silicon）所有 `xcodebuild` 必须加 `ONLY_ACTIVE_ARCH=YES ARCHS=arm64`。默认通用架构构建会让本地框架/包产物只构建单一架构，导致另一端架构链接报 "built for incompatible target"。
2. **FlashNoteCore 集成方式**：XcodeGen 2.46 的本地 Swift Package 引用在 Xcode 26.6 下多平台产物路径解析错误（iOS target 链接到 macOS 产物目录）。**改用两个 framework target**（`FlashNoteCore` iOS 变体 + `FlashNoteCoreMac` macOS 变体，模块名均为 FlashNoteCore），App/测试 target 依赖对应变体。包本体保留给 CLI 测试（`cd FlashNoteCore && swift test`）。
3. **测试 target 配置**：需 `GENERATE_INFOPLIST_FILE: YES`、`TEST_HOST` + `BUNDLE_LOADER`（指向宿主 App）、App target 需 `ENABLE_TESTABILITY: YES`（否则 `@testable import` 报 "unable to resolve Swift module dependency"）。
4. **测试文件的模块导入**：共享 `Tests/` 同时被双平台测试 target 编译，必须用条件导入：
   ```swift
   #if os(macOS)
   @testable import FlashNoteMac
   #else
   @testable import FlashNote
   #endif
   ```
5. **iOS 模拟器目的地不可用**：本机 `xcodebuild` 无法发现模拟器目的地（simctl 可见、SDK 可见，但 destination 列表只有 macOS）。iOS 构建验证改用 `-sdk iphoneos CODE_SIGNING_ALLOWED=NO`（真实 iOS SDK 编译，免签名）；iOS 测试执行待用户运行 `sudo xcodebuild -runFirstLaunch` 修复模拟器注册后补充。共享逻辑测试已在 macOS 测试 target 覆盖。
6. **macOS 测试命令**（本计划内统一）：
   ```bash
   xcodebuild -project FlashNote.xcodeproj -scheme FlashNoteMac -destination 'platform=macOS' ONLY_ACTIVE_ARCH=YES ARCHS=arm64 test
   ```
   **iOS 构建命令**（统一）：
   ```bash
   xcodebuild -project FlashNote.xcodeproj -scheme FlashNote -sdk iphoneos CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=YES ARCHS=arm64 build
   ```
7. 已确认可用的最终 `project.yml` 结构（双 app + 双 framework + 双测试 target）见 Task 1 Step 1 的修订版（下文已更新）。

---

## 文件结构

```
仓库根 /
├── project.yml                          # XcodeGen 配置（双 target + 双测试 target + 本地包依赖）
├── App/
│   ├── FlashNoteApp.swift               # @main 条件编译（macOS/iOS 各自入口）
│   └── RootView.swift                   # macOS 三栏 / iOS TabView
├── Features/
│   ├── Recorder/
│   │   ├── RecorderViewModel.swift      # 状态机 + 编排（可单测）
│   │   ├── RecorderView.swift           # 录音界面（双平台共用）
│   │   ├── WaveformView.swift           # 电平波形
│   │   └── LiveTranscriptView.swift     # 实时转写滚动
│   ├── Recordings/
│   │   ├── RecordingListView.swift      # 录音列表（含状态徽章）
│   │   └── RecordingRow.swift
│   └── Detail/
│       └── RecordingDetailView.swift    # 详情（全文转写页签 M1，纪要/播放占位）
├── Services/
│   ├── Audio/
│   │   ├── AudioRecording.swift         # 协议（可注入 mock）
│   │   └── AudioService.swift           # AVAudioEngine 实现
│   └── Speech/
│       ├── LiveTranscriptionEngine.swift # 协议（TranscriptionEngine + onPartialText + append）
│       ├── SpeechEngine.swift           # SFSpeechRecognizer 实现
│       └── SpeechAuthorization.swift    # 授权请求 + 错误映射（纯函数可测）
├── DesignSystem/
│   ├── AppTheme.swift                   # 专业蓝色彩体系
│   ├── AppIcons.swift                   # SF Symbols 映射
│   └── Components.swift                 # Badge / Card / RecordButton
├── Resources/
│   └── Assets.xcassets                  # AccentColor（#0A84FF）+ 占位 AppIcon
└── Tests/
    ├── SpeechAuthorizationTests.swift
    ├── RecorderViewModelTests.swift
    └── Support/InMemoryStore.swift      # RecordingStore 内存实现（测试替身）
```

**本计划之外（后续里程碑）：** M2 文件导入 + Whisper/云端转写；M3 AI 纪要 UI + LLM 设置；M4 CloudKit/iCloud 同步 + 文件夹 + 搜索；M5 图标打磨、空状态、错误恢复、上架。M1 的详情页「AI 纪要」「播放」页签为占位。

---

### Task 1: 工程骨架（XcodeGen + 双 target + 核心包接入）

**Files:**
- Create: `project.yml`
- Create: `App/FlashNoteApp.swift`
- Create: `App/RootView.swift`
- Create: `Resources/Assets.xcassets/Contents.json`
- Create: `Resources/Assets.xcassets/AccentColor.colorset/Contents.json`
- Create: `Resources/Assets.xcassets/AppIcon.appiconset/Contents.json`
- Create: `.gitignore` 追加（`FlashNote.xcodeproj` 由 xcodegen 生成，不入库；见 Step 6）

- [ ] **Step 1: 写 project.yml**

```yaml
name: FlashNote
options:
  bundleIdPrefix: com.flashnote
  deploymentTarget:
    iOS: "17.0"
    macOS: "14.0"
  createIntermediateGroups: true
settings:
  base:
    SWIFT_VERSION: "5.10"
targets:
  # FlashNoteCore 以 framework target 集成（XcodeGen 本地包引用在 Xcode 26.6 下
  # 多平台产物路径解析错误）。同一份 Sources 两个平台变体，模块名均为 FlashNoteCore。
  FlashNoteCore:
    type: framework
    platform: iOS
    sources:
      - path: FlashNoteCore/Sources
    settings:
      base:
        PRODUCT_NAME: FlashNoteCore
        PRODUCT_MODULE_NAME: FlashNoteCore
        GENERATE_INFOPLIST_FILE: YES
        SKIP_INSTALL: YES
        DEFINES_MODULE: YES
  FlashNoteCoreMac:
    type: framework
    platform: macOS
    sources:
      - path: FlashNoteCore/Sources
    settings:
      base:
        PRODUCT_NAME: FlashNoteCore
        PRODUCT_MODULE_NAME: FlashNoteCore
        GENERATE_INFOPLIST_FILE: YES
        SKIP_INSTALL: YES
        DEFINES_MODULE: YES
  FlashNote:
    type: application
    platform: iOS
    sources:
      - path: App
      - path: Features
      - path: Services
      - path: DesignSystem
      - path: Resources
    dependencies:
      - target: FlashNoteCore
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.flashnote.app
        PRODUCT_NAME: FlashNote
        PRODUCT_MODULE_NAME: FlashNote
        ENABLE_TESTABILITY: YES
        GENERATE_INFOPLIST_FILE: YES
        INFOPLIST_KEY_UILaunchScreen_Generation: YES
        INFOPLIST_KEY_NSMicrophoneUsageDescription: 用于录制音频并实时转写
        INFOPLIST_KEY_NSSpeechRecognitionUsageDescription: 用于实时语音转写
        ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon
        TARGETED_DEVICE_FAMILY: "1,2"
        CODE_SIGN_STYLE: Automatic
    scheme:
      testTargets:
        - FlashNoteTests
  FlashNoteTests:
    type: bundle.unit-test
    platform: iOS
    sources:
      - path: Tests
    dependencies:
      - target: FlashNote
      - target: FlashNoteCore
    settings:
      base:
        PRODUCT_NAME: FlashNoteTests
        PRODUCT_MODULE_NAME: FlashNoteTests
        GENERATE_INFOPLIST_FILE: YES
        TEST_HOST: "$(BUILT_PRODUCTS_DIR)/FlashNote.app/FlashNote"
        BUNDLE_LOADER: "$(TEST_HOST)"
  FlashNoteMac:
    type: application
    platform: macOS
    sources:
      - path: App
      - path: Features
      - path: Services
      - path: DesignSystem
      - path: Resources
    dependencies:
      - target: FlashNoteCoreMac
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.flashnote.mac
        PRODUCT_NAME: FlashNoteMac
        PRODUCT_MODULE_NAME: FlashNoteMac
        ENABLE_TESTABILITY: YES
        GENERATE_INFOPLIST_FILE: YES
        INFOPLIST_KEY_NSMicrophoneUsageDescription: 用于录制音频并实时转写
        INFOPLIST_KEY_NSSpeechRecognitionUsageDescription: 用于实时语音转写
        ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon
        CODE_SIGN_STYLE: Automatic
    scheme:
      testTargets:
        - FlashNoteMacTests
  FlashNoteMacTests:
    type: bundle.unit-test
    platform: macOS
    sources:
      - path: Tests
    dependencies:
      - target: FlashNoteMac
      - target: FlashNoteCoreMac
    settings:
      base:
        PRODUCT_NAME: FlashNoteMacTests
        PRODUCT_MODULE_NAME: FlashNoteMacTests
        GENERATE_INFOPLIST_FILE: YES
        TEST_HOST: "$(BUILT_PRODUCTS_DIR)/FlashNoteMac.app/Contents/MacOS/FlashNoteMac"
        BUNDLE_LOADER: "$(TEST_HOST)"
```

- [ ] **Step 2: 写入口与根视图**

`App/FlashNoteApp.swift`:

```swift
import SwiftUI

#if os(macOS)
@main
struct FlashNoteMacApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
#else
@main
struct FlashNoteApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
#endif
```

`App/RootView.swift`（M1 骨架：iOS TabView 占位、macOS 三栏占位；后续任务填充真实内容）：

```swift
import SwiftUI

/// 平台根视图：macOS 三栏 / iOS 标签栏。
struct RootView: View {
    var body: some View {
#if os(macOS)
        NavigationSplitView {
            Text("文件夹")
                .navigationTitle("FlashNote")
        } content: {
            Text("录音列表")
        } detail: {
            Text("详情")
        }
        .frame(minWidth: 900, minHeight: 600)
#else
        TabView {
            Text("录音")
                .tabItem { Label("录音", systemImage: "mic.fill") }
            Text("文件夹")
                .tabItem { Label("文件夹", systemImage: "folder.fill") }
            Text("设置")
                .tabItem { Label("设置", systemImage: "gearshape.fill") }
        }
#endif
    }
}
```

- [ ] **Step 3: 写资源目录**

`Resources/Assets.xcassets/Contents.json`:

```json
{
  "info" : { "author" : "xcode", "version" : 1 }
}
```

`Resources/Assets.xcassets/AccentColor.colorset/Contents.json`（专业蓝 #0A84FF）：

```json
{
  "colors" : [
    {
      "color" : {
        "color-space" : "srgb",
        "components" : { "alpha" : "1.000", "blue" : "1.000", "green" : "0.518", "red" : "0.039" }
      },
      "idiom" : "universal"
    }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
```

`Resources/Assets.xcassets/AppIcon.appiconset/Contents.json`（占位，图标 M5 制作）：

```json
{
  "images" : [ { "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" } ],
  "info" : { "author" : "xcode", "version" : 1 }
}
```

- [ ] **Step 4: 生成工程并构建双 target**

```bash
xcodegen generate
xcodebuild -project FlashNote.xcodeproj -scheme FlashNote -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
xcodebuild -project FlashNote.xcodeproj -scheme FlashNoteMac -destination 'platform=macOS' build
```
Expected: 两个 target 均 `BUILD SUCCEEDED`。（AppIcon 缺图可能产生警告，不影响构建；AccentColor 生效。）

- [ ] **Step 5: 更新 .gitignore**

在 `.gitignore` 末尾追加：

```
FlashNote.xcodeproj/
```

- [ ] **Step 6: 提交**

```bash
git add project.yml App Resources .gitignore && git commit -m "feat: scaffold FlashNote app (XcodeGen, dual targets, core package)"
```

---

### Task 2: 设计系统

**Files:**
- Create: `DesignSystem/AppTheme.swift`
- Create: `DesignSystem/AppIcons.swift`
- Create: `DesignSystem/Components.swift`
- Test: `Tests/DesignSystemTests.swift`

- [ ] **Step 1: 写失败测试**

`Tests/DesignSystemTests.swift`：

```swift
import Testing
@testable import FlashNote

struct DesignSystemTests {
    @Test func accentColorMatchesProfessionalBlue() {
        let color = AppTheme.accent
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        #if os(macOS)
        let resolved = color.usingColorSpace(.sRGB)!
        #else
        let resolved = color
        #endif
        resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        #expect(abs(red - 0.039) < 0.01)
        #expect(abs(green - 0.518) < 0.01)
        #expect(abs(blue - 1.0) < 0.01)
    }

    @Test func statusBadgeStyling() {
        #expect(RecordingStatusView.title(for: .recording) == "录音中")
        #expect(RecordingStatusView.title(for: .transcribed) == "已转写")
        #expect(RecordingStatusView.title(for: .summarized) == "已出纪要")
    }
}
```

- [ ] **Step 2: 运行确认失败**

```bash
xcodebuild -project FlashNote.xcodeproj -scheme FlashNoteMac -destination 'platform=macOS' test 2>&1 | tail -5
```
Expected: 编译失败——找不到 `AppTheme` / `RecordingStatusView`。

- [ ] **Step 3: 实现**

`DesignSystem/AppTheme.swift`:

```swift
import SwiftUI

/// 设计语言：专业蓝（与 Assets 的 AccentColor 一致）。
enum AppTheme {
    static let accent = Color(red: 0.039, green: 0.518, blue: 1.0)          // #0A84FF
    static let background = Color(red: 0.961, green: 0.961, blue: 0.969)    // #F5F5F7
    static let cardBackground = Color.white
    static let primaryText = Color(red: 0.114, green: 0.114, blue: 0.122)   // #1D1D1F
    static let secondaryText = Color(red: 0.557, green: 0.557, blue: 0.576) // #8E8E93
    static let destructive = Color(red: 1.0, green: 0.231, blue: 0.188)     // #FF3B30
    static let success = Color(red: 0.102, green: 0.62, blue: 0.361)        // #1A9E5C
    static let successBackground = Color(red: 0.91, green: 0.969, blue: 0.933)
    static let infoBackground = Color(red: 0.91, green: 0.945, blue: 1.0)
}
```

`DesignSystem/AppIcons.swift`:

```swift
import SwiftUI

/// SF Symbols 映射（扁平线性图标）。
enum AppIcons {
    static let mic = "mic.fill"
    static let folder = "folder.fill"
    static let book = "book.closed.fill"
    static let chat = "bubble.left.and.bubble.right.fill"
    static let settings = "gearshape.fill"
    static let search = "magnifyingglass"
    static let play = "play.fill"
    static let document = "doc.text"
    static let sparkle = "sparkles"
    static let checkmark = "checkmark"
    static let plus = "plus"
    static let pause = "pause.fill"
    static let stop = "stop.fill"
    static let importFile = "square.and.arrow.down"
    static let clock = "clock"
    static let delete = "trash"
}
```

`DesignSystem/Components.swift`:

```swift
import SwiftUI

/// 状态徽章（录音中/已转写/已出纪要）。
struct RecordingStatusView: View {
    let status: RecordingStatus

    var body: some View {
        Text(Self.title(for: status))
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(background, in: Capsule())
            .foregroundStyle(foreground)
    }

    static func title(for status: RecordingStatus) -> String {
        switch status {
        case .recording: "录音中"
        case .transcribed: "已转写"
        case .summarized: "已出纪要"
        }
    }

    private var background: Color {
        switch status {
        case .recording: AppTheme.infoBackground
        case .transcribed: AppTheme.successBackground
        case .summarized: AppTheme.infoBackground
        }
    }

    private var foreground: Color {
        switch status {
        case .recording: AppTheme.accent
        case .transcribed: AppTheme.success
        case .summarized: AppTheme.accent
        }
    }
}

/// 卡片容器。
struct Card<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(14)
            .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: .black.opacity(0.05), radius: 4, y: 1)
    }
}
```

- [ ] **Step 4: 运行确认通过**

```bash
xcodebuild -project FlashNote.xcodeproj -scheme FlashNoteMac -destination 'platform=macOS' test 2>&1 | tail -3
```
Expected: `FlashNoteMacTests` 通过（2 个测试）。

- [ ] **Step 5: 提交**

```bash
git add DesignSystem Tests && git commit -m "feat: add design system (theme, icons, components)"
```

---

### Task 3: 依赖装配（AppEnvironment + 存储接入）

**Files:**
- Create: `App/AppEnvironment.swift`
- Test: `Tests/AppEnvironmentTests.swift`

- [ ] **Step 1: 写失败测试**

`Tests/AppEnvironmentTests.swift`：

```swift
import Testing
import Foundation
@testable import FlashNote

struct AppEnvironmentTests {
    @Test func liveEnvironmentCreatesFileStore() throws {
        let env = AppEnvironment.makeLive()
        #expect(env.store is FileRecordingStore)
    }

    @Test func storeDirectoryUsesApplicationSupport() {
        let dir = AppEnvironment.defaultStoreDirectory()
        #expect(dir.lastPathComponent == "FlashNote")
        #expect(dir.path.contains("Application Support"))
    }

    @Test func storeRoundTripsRecording() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("EnvTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try FileRecordingStore(root: root)
        var rec = Recording(title: "测试")
        rec.markTranscribed()
        try store.upsertRecording(rec)
        #expect(try store.fetchRecording(id: rec.id) == rec)
    }
}
```

- [ ] **Step 2: 运行确认失败**

```bash
xcodebuild -project FlashNote.xcodeproj -scheme FlashNoteMac -destination 'platform=macOS' test 2>&1 | tail -5
```
Expected: 编译失败——找不到 `AppEnvironment`。

- [ ] **Step 3: 实现**

`App/AppEnvironment.swift`:

```swift
import Foundation
import SwiftUI
import FlashNoteCore

/// 全局依赖装配：存储 + 设置。App 层通过 Environment 注入。
@Observable
final class AppEnvironment {
    let store: RecordingStore

    init(store: RecordingStore) {
        self.store = store
    }

    /// 生产装配：文件存储落在 Application Support/FlashNote。
    static func makeLive() -> AppEnvironment {
        let store = try! FileRecordingStore(root: Self.defaultStoreDirectory())
        return AppEnvironment(store: store)
    }

    /// 默认数据目录：~/Library/Application Support/FlashNote
    static func defaultStoreDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("FlashNote", isDirectory: true)
    }
}

private struct AppEnvironmentKey: EnvironmentKey {
    static let defaultValue: AppEnvironment? = nil
}

extension EnvironmentValues {
    var appEnvironment: AppEnvironment? {
        get { self[AppEnvironmentKey.self] }
        set { self[AppEnvironmentKey.self] = newValue }
    }
}
```

`App/FlashNoteApp.swift` 与 `App/RootView.swift` 更新——注入环境：

`App/FlashNoteApp.swift`：

```swift
import SwiftUI

#if os(macOS)
@main
struct FlashNoteMacApp: App {
    @State private var environment = AppEnvironment.makeLive()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.appEnvironment, environment)
        }
    }
}
#else
@main
struct FlashNoteApp: App {
    @State private var environment = AppEnvironment.makeLive()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.appEnvironment, environment)
        }
    }
}
#endif
```

- [ ] **Step 4: 运行确认通过**

```bash
xcodebuild -project FlashNote.xcodeproj -scheme FlashNoteMac -destination 'platform=macOS' test 2>&1 | tail -3
```
Expected: 全部通过（含 3 个新测试）。

- [ ] **Step 5: 提交**

```bash
git add App Tests && git commit -m "feat: wire AppEnvironment with FileRecordingStore"
```

---

### Task 4: Speech 授权映射

**Files:**
- Create: `Services/Speech/SpeechAuthorization.swift`
- Test: `Tests/SpeechAuthorizationTests.swift`

- [ ] **Step 1: 写失败测试**

`Tests/SpeechAuthorizationTests.swift`：

```swift
import Testing
import Speech
@testable import FlashNote

struct SpeechAuthorizationTests {
    @Test func authorizedMapsToNil() {
        #expect(SpeechAuthorization.error(for: .authorized) == nil)
    }

    @Test func deniedMapsToPermissionDenied() {
        #expect(SpeechAuthorization.error(for: .denied) == .permissionDenied)
        #expect(SpeechAuthorization.error(for: .restricted) == .permissionDenied)
        #expect(SpeechAuthorization.error(for: .notDetermined) == .permissionDenied)
    }
}
```

注意：`TranscriptionError` 需 `Equatable`（核心包已满足）才能用 `==` 断言；测试文件需要 `import FlashNoteCore` 吗？`@testable import FlashNote` 会再导出其公开 API——不行，`@testable` 不传递依赖。**需要显式 `import FlashNoteCore`**。

- [ ] **Step 2: 运行确认失败**

```bash
xcodebuild -project FlashNote.xcodeproj -scheme FlashNoteMac -destination 'platform=macOS' test 2>&1 | tail -5
```
Expected: 编译失败——找不到 `SpeechAuthorization`。

- [ ] **Step 3: 实现**

`Services/Speech/SpeechAuthorization.swift`:

```swift
import Foundation
import Speech
import FlashNoteCore

/// Speech 授权：请求权限并把系统状态映射为核心层 TranscriptionError。
enum SpeechAuthorization {
    /// 请求麦克风 + 语音识别权限。返回 nil 表示可用，否则为对应错误。
    static func requestPermissions() async -> TranscriptionError? {
        // 语音识别权限
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        if let speechError = error(for: speech) { return speechError }
        return nil
    }

    /// 纯函数映射（可测）：授权状态 → 核心错误。
    static func error(for status: SFSpeechRecognizerAuthorizationStatus) -> TranscriptionError? {
        switch status {
        case .authorized: nil
        case .denied, .restricted, .notDetermined: .permissionDenied
        @unknown default: .permissionDenied
        }
    }
}
```

- [ ] **Step 4: 运行确认通过**

```bash
xcodebuild -project FlashNote.xcodeproj -scheme FlashNoteMac -destination 'platform=macOS' test 2>&1 | tail -3
```
Expected: 全部通过（含 2 个新测试）。

- [ ] **Step 5: 提交**

```bash
git add Services Tests && git commit -m "feat: add speech authorization mapping"
```

---

### Task 5: SpeechEngine（核心协议实现）

**Files:**
- Create: `Services/Speech/LiveTranscriptionEngine.swift`
- Create: `Services/Speech/SpeechEngine.swift`

本任务无单测（SFSpeechRecognizer 需要真实麦克风/语音；逻辑薄），验证方式 = 双 target 构建通过 + Task 10 的 macOS 手动真机验证。

- [ ] **Step 1: 定义协议**

`Services/Speech/LiveTranscriptionEngine.swift`:

```swift
import Foundation
import AVFoundation
import FlashNoteCore

/// App 层直播转写引擎：核心协议 + 局部文本直播通道（UI 实时高亮用）。
protocol LiveTranscriptionEngine: TranscriptionEngine {
    /// 局部（未定稿）文本：nil 表示当前无局部文本。
    var onPartialText: ((String?) -> Void)? { get set }
    /// 向识别器推送音频缓冲（由 AudioService 调用）。
    func append(_ buffer: AVAudioPCMBuffer)
}
```

- [ ] **Step 2: 实现 SpeechEngine**

`Services/Speech/SpeechEngine.swift`:

```swift
import Foundation
import Speech
import AVFoundation
import FlashNoteCore

/// Apple 系统转写引擎（zh-CN）。局部文本走 onPartialText；定稿段落走 onSegment。
final class SpeechEngine: LiveTranscriptionEngine {
    let displayName = "Apple 系统转写"
    let isRealtime = true

    var onSegment: ((TranscriptSegment) -> Void)?
    var onError: ((Error) -> Void)?
    var onPartialText: ((String?) -> Void)?

    private let recognizer: SFSpeechRecognizer
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var started = false

    /// 初始化失败（识别器不可用）时返回 nil。
    init?(locale: Locale = Locale(identifier: "zh-CN")) {
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            return nil
        }
        self.recognizer = recognizer
    }

    func start() throws {
        guard !started else { throw TranscriptionError.invalidState("already started") }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        self.request = request

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let result {
                if result.isFinal {
                    let text = result.bestTranscription.formattedString
                    if !text.isEmpty {
                        self.onSegment?(TranscriptSegment(startTime: 0, text: text, isFinal: true))
                    }
                    self.onPartialText?(nil)
                } else {
                    self.onPartialText?(result.bestTranscription.formattedString)
                }
            }
            if let error, (error as NSError).code != 216 { // 216 = 用户取消
                self.onError?(TranscriptionError.engineFailed(error.localizedDescription))
            }
        }
        started = true
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        request?.append(buffer)
    }

    func cancel() {
        task?.cancel()
        task = nil
        request = nil
        started = false
        onPartialText?(nil)
    }
}
```

- [ ] **Step 3: 构建验证双 target**

```bash
xcodebuild -project FlashNote.xcodeproj -scheme FlashNote -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -1
xcodebuild -project FlashNote.xcodeproj -scheme FlashNoteMac -destination 'platform=macOS' build 2>&1 | tail -1
```
Expected: 均 `BUILD SUCCEEDED`。

- [ ] **Step 4: 提交**

```bash
git add Services && git commit -m "feat: add SpeechEngine (core protocol implementation)"
```

---

### Task 6: AudioService（录音采集）

**Files:**
- Create: `Services/Audio/AudioRecording.swift`
- Create: `Services/Audio/AudioService.swift`
- Test: `Tests/AudioServiceTests.swift`

- [ ] **Step 1: 写失败测试**

`Tests/AudioServiceTests.swift`：

```swift
import Testing
import AVFoundation
@testable import FlashNote

struct AudioServiceTests {
    @Test func rmsOfSilenceIsZero() {
        #expect(AudioService.rms([Float](repeating: 0, count: 64)) == 0)
    }

    @Test func rmsOfFullScaleIsNearOne() {
        let samples = [Float](repeating: 1.0, count: 64)
        #expect(AudioService.rms(samples) > 0.95)
    }

    @Test func rmsOfMixedSamplesIsPositiveAndBounded() {
        let samples: [Float] = (0..<64).map { Float($0 % 7) / 7.0 }
        let rms = AudioService.rms(samples)
        #expect(rms > 0)
        #expect(rms <= 1)
    }
}
```

- [ ] **Step 2: 运行确认失败**

```bash
xcodebuild -project FlashNote.xcodeproj -scheme FlashNoteMac -destination 'platform=macOS' test 2>&1 | tail -5
```
Expected: 编译失败——找不到 `AudioService`。

- [ ] **Step 3: 实现**

`Services/Audio/AudioRecording.swift`:

```swift
import Foundation
import AVFoundation

/// 录音采集抽象（测试替身可注入 RecorderViewModel）。
protocol AudioRecording: AnyObject {
    /// 电平 0...1（RMS）。
    var onLevel: ((Float) -> Void)? { get set }
    /// 原始 PCM 缓冲（供识别引擎消费）。
    var onBuffer: ((AVAudioPCMBuffer) -> Void)? { get set }
    var isRecording: Bool { get }
    func startRecording(to url: URL) throws
    func pause()
    func resume()
    func stop()
}
```

`Services/Audio/AudioService.swift`:

```swift
import Foundation
import AVFoundation

/// AVAudioEngine 采集：输入 tap → 写 AVAudioFile（PCM .caf）+ 电平回调 + 缓冲泵出。
final class AudioService: AudioRecording {
    var onLevel: ((Float) -> Void)?
    var onBuffer: ((AVAudioPCMBuffer) -> Void)?
    private(set) var isRecording = false

    private let engine = AVAudioEngine()
    private var file: AVAudioFile?

    func startRecording(to url: URL) throws {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        file = try AVAudioFile(forWriting: url, settings: format.settings)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.handle(buffer)
        }
        engine.prepare()
        try engine.start()
        isRecording = true
    }

    func pause() {
        guard isRecording else { return }
        engine.pause()
    }

    func resume() {
        guard isRecording else { return }
        try? engine.start()
    }

    func stop() {
        guard isRecording else { return }
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        file = nil
        isRecording = false
    }

    private func handle(_ buffer: AVAudioPCMBuffer) {
        do { try file?.write(from: buffer) } catch { /* 写盘失败不阻断识别 */ }
        onLevel?(Self.rms(buffer))
        onBuffer?(buffer)
    }

    /// 缓冲 → 归一化 RMS（0...1）。
    static func rms(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let channel = buffer.floatChannelData?[0] else { return 0 }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return 0 }
        let samples = Array(UnsafeBufferPointer(start: channel, count: frames))
        return rms(samples)
    }

    /// 采样数组 → 归一化 RMS（0...1）。纯函数（可测）。
    static func rms(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        let sum = samples.reduce(Float(0)) { $0 + $1 * $1 }
        return min(1, sqrt(sum / Float(samples.count)))
    }
}
```

- [ ] **Step 4: 运行确认通过**

```bash
xcodebuild -project FlashNote.xcodeproj -scheme FlashNoteMac -destination 'platform=macOS' test 2>&1 | tail -3
```
Expected: 全部通过（含 3 个新测试）。

- [ ] **Step 5: 提交**

```bash
git add Services Tests && git commit -m "feat: add AudioService (AVAudioEngine recording + level meter)"
```

---

### Task 7: RecorderViewModel（状态机与编排）

**Files:**
- Create: `Features/Recorder/RecorderViewModel.swift`
- Create: `Tests/Support/InMemoryStore.swift`
- Test: `Tests/RecorderViewModelTests.swift`

- [ ] **Step 1: 写失败测试与测试替身**

`Tests/Support/InMemoryStore.swift`：

```swift
import Foundation
import FlashNoteCore

/// RecordingStore 内存实现（测试替身）。
final class InMemoryStore: RecordingStore {
    private var recordings: [UUID: Recording] = [:]
    private var transcripts: [UUID: Transcript] = [:]
    private var minutes: [UUID: [Minutes]] = [:]
    private var folders: [UUID: Folder] = [:]

    func fetchRecordings() throws -> [Recording] {
        recordings.values.sorted { $0.createdAt > $1.createdAt }
    }
    func fetchRecording(id: UUID) throws -> Recording? { recordings[id] }
    func upsertRecording(_ recording: Recording) throws { recordings[recording.id] = recording }
    func deleteRecording(id: UUID) throws { recordings[id] = nil }
    func fetchTranscript(recordingID: UUID) throws -> Transcript? { transcripts[recordingID] }
    func upsertTranscript(_ transcript: Transcript) throws { transcripts[transcript.recordingID] = transcript }
    func fetchMinutes(recordingID: UUID) throws -> [Minutes] { minutes[recordingID] ?? [] }
    func upsertMinutes(_ minutes: Minutes) throws { self.minutes[minutes.recordingID, default: []].append(minutes) }
    func fetchFolders() throws -> [Folder] { folders.values.sorted { $0.createdAt < $1.createdAt } }
    func upsertFolder(_ folder: Folder) throws { folders[folder.id] = folder }
}
```

`Tests/RecorderViewModelTests.swift`：

```swift
import Testing
import Foundation
import AVFoundation
@testable import FlashNote
import FlashNoteCore

/// 测试替身：立即进入录音状态，可编程推送局部/定稿文本。
final class MockLiveEngine: LiveTranscriptionEngine {
    let displayName = "Mock"
    let isRealtime = true
    var onSegment: ((TranscriptSegment) -> Void)?
    var onError: ((Error) -> Void)?
    var onPartialText: ((String?) -> Void)?
    private(set) var started = false
    private(set) var cancelled = false
    private(set) var appendedBuffers: [AVAudioPCMBuffer] = []

    func start() throws {
        guard !started else { throw TranscriptionError.invalidState("already started") }
        started = true
    }
    func append(_ buffer: AVAudioPCMBuffer) { appendedBuffers.append(buffer) }
    func cancel() { cancelled = true; started = false }

    func emitPartial(_ text: String?) { onPartialText?(text) }
    func emitFinal(_ text: String) { onSegment?(TranscriptSegment(startTime: 0, text: text, isFinal: true)) }
}

/// 测试替身：记录生命周期，不碰真实硬件。
final class MockAudio: AudioRecording {
    var onLevel: ((Float) -> Void)?
    var onBuffer: ((AVAudioPCMBuffer) -> Void)?
    private(set) var isRecording = false
    private(set) var startedURL: URL?
    private(set) var stopped = false
    private(set) var pausedCount = 0
    private(set) var resumedCount = 0
    var failToStart = false

    func startRecording(to url: URL) throws {
        if failToStart { throw TranscriptionError.engineFailed("mic unavailable") }
        startedURL = url
        isRecording = true
    }
    func pause() { pausedCount += 1 }
    func resume() { resumedCount += 1 }
    func stop() { stopped = true; isRecording = false }
}

struct RecorderViewModelTests {
    private func makeVM(
        audio: MockAudio = MockAudio(),
        engine: MockLiveEngine = MockLiveEngine(),
        store: InMemoryStore = InMemoryStore()
    ) -> (RecorderViewModel, MockAudio, MockLiveEngine, InMemoryStore) {
        let vm = RecorderViewModel(audio: audio, engine: engine, store: store)
        return (vm, audio, engine, store)
    }

    @Test func startEntersRecordingAndWiresCallbacks() throws {
        let (vm, audio, engine, _) = makeVM()
        try vm.start()
        #expect(vm.phase == .recording)
        #expect(audio.isRecording)
        #expect(engine.started)
        #expect(vm.recordingID != nil)
        #expect(vm.recordingTitle == "未命名录音")
    }

    @Test func startFailureSetsError() {
        let audio = MockAudio(); audio.failToStart = true
        let (vm, _, _, _) = makeVM(audio: audio)
        #expect(throws: TranscriptionError.self) { try vm.start() }
        #expect(vm.phase == .idle)
    }

    @Test func partialAndFinalSegmentsUpdateUI() throws {
        let (vm, _, engine, _) = makeVM()
        try vm.start()
        engine.emitPartial("你好")
        #expect(vm.partialText == "你好")
        engine.emitPartial("你好世界")
        #expect(vm.partialText == "你好世界")
        engine.emitFinal("你好世界。")
        #expect(vm.partialText == nil)
        #expect(vm.segments.count == 1)
    }

    @Test func stopSavesRecordingAndTranscript() throws {
        let (vm, audio, engine, store) = makeVM()
        try vm.start()
        engine.emitFinal("这是一段转写。")
        vm.stop()
        #expect(vm.phase == .idle)
        #expect(audio.stopped)
        #expect(engine.cancelled)
        let recID = try #require(vm.recordingID)
        let savedRec = try store.fetchRecording(id: recID)
        #expect(savedRec?.status == .transcribed)
        let savedTranscript = try store.fetchTranscript(recordingID: recID)
        #expect(savedTranscript?.fullText == "这是一段转写。")
    }

    @Test func pauseResumeTransitions() throws {
        let (vm, audio, _, _) = makeVM()
        try vm.start()
        vm.pause()
        #expect(vm.phase == .paused)
        #expect(audio.pausedCount == 1)
        vm.resume()
        #expect(vm.phase == .recording)
        #expect(audio.resumedCount == 1)
    }

    @Test func elapsedFormatting() {
        #expect(RecorderViewModel.formatElapsed(0) == "00:00:00")
        #expect(RecorderViewModel.formatElapsed(3725) == "01:02:05")
        #expect(RecorderViewModel.formatElapsed(59) == "00:00:59")
    }
}
```

- [ ] **Step 2: 运行确认失败**

```bash
xcodebuild -project FlashNote.xcodeproj -scheme FlashNoteMac -destination 'platform=macOS' test 2>&1 | tail -5
```
Expected: 编译失败——找不到 `RecorderViewModel`。

- [ ] **Step 3: 实现 RecorderViewModel**

注意：**授权检查不在 ViewModel 内做**——`start()` 保持纯编排（可单测）；授权由 RecorderView（视图层）在创建 ViewModel 前 async 调用 `SpeechAuthorization.requestPermissions()`。

`Features/Recorder/RecorderViewModel.swift`:

```swift
import Foundation
import AVFoundation
import FlashNoteCore

/// 录音页状态机：idle → recording ⇄ paused → idle。
/// 编排 音频采集 + 实时转写 + 本地保存；依赖协议注入，可单测。
@Observable
final class RecorderViewModel {
    enum Phase: Equatable {
        case idle
        case recording
        case paused
    }

    private(set) var phase: Phase = .idle
    private(set) var elapsed: TimeInterval = 0
    private(set) var level: Float = 0
    private(set) var segments: [TranscriptSegment] = []
    private(set) var partialText: String?
    private(set) var recordingID: UUID?
    private(set) var recordingTitle = "未命名录音"
    private(set) var errorMessage: String?

    private let audio: AudioRecording
    private let engine: LiveTranscriptionEngine
    private let store: RecordingStore
    private var service: TranscriptionService?
    private var timer: Timer?

    init(audio: AudioRecording, engine: LiveTranscriptionEngine, store: RecordingStore) {
        self.audio = audio
        self.engine = engine
        self.store = store
        engine.onPartialText = { [weak self] text in
            self?.partialText = text
        }
        engine.onError = { [weak self] _ in
            self?.errorMessage = "转写引擎出错，请重试"
        }
    }

    func start() throws {
        guard phase == .idle else { throw TranscriptionError.invalidState("already started") }

        let id = UUID()
        recordingID = id
        service = TranscriptionService(recordingID: id, engine: engine)
        segments = []
        partialText = nil
        elapsed = 0

        let fileURL = Self.recordingFileURL(for: id)
        do {
            try audio.startRecording(to: fileURL)
        } catch {
            phase = .idle
            throw error
        }
        try service?.begin()
        phase = .recording
        startTimer()
        wireAudio()
    }

    func pause() {
        guard phase == .recording else { return }
        audio.pause()
        phase = .paused
    }

    func resume() {
        guard phase == .paused else { return }
        audio.resume()
        phase = .recording
    }

    func stop() {
        guard phase != .idle else { return }
        audio.stop()
        stopTimer()
        engine.cancel()
        guard let service, let recordingID else { return }

        let transcript = service.finish()
        segments = transcript.segments
        var recording = Recording(id: recordingID, title: recordingTitle)
        recording.duration = elapsed
        recording.audioFilename = "\(recordingID.uuidString).caf"
        recording.markTranscribed()
        do {
            try store.upsertRecording(recording)
            try store.upsertTranscript(transcript)
        } catch {
            errorMessage = "保存失败：\(error.localizedDescription)"
        }
        phase = .idle
    }

    private func wireAudio() {
        audio.onLevel = { [weak self] level in
            self?.level = level
        }
        audio.onBuffer = { [weak self] buffer in
            self?.engine.append(buffer)
        }
    }

    private func startTimer() {
        timer?.invalidate()
        let start = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.elapsed = Date().timeIntervalSince(start)
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    /// 录音文件位置：Application Support/FlashNote/audio/{id}.caf
    static func recordingFileURL(for id: UUID) -> URL {
        AppEnvironment.defaultStoreDirectory()
            .appendingPathComponent("audio", isDirectory: true)
            .appendingPathComponent("\(id.uuidString).caf")
    }

    /// 秒 → "HH:MM:SS"。纯函数（可测）。
    static func formatElapsed(_ total: TimeInterval) -> String {
        let total = Int(total)
        return String(format: "%02d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }
}
```

- [ ] **Step 4: 运行确认通过**

```bash
xcodebuild -project FlashNote.xcodeproj -scheme FlashNoteMac -destination 'platform=macOS' test 2>&1 | tail -3
```
Expected: 全部通过（含 6 个 RecorderViewModelTests）。

- [ ] **Step 5: 提交**

```bash
git add Features Tests && git commit -m "feat: add RecorderViewModel state machine with tests"
```

---

### Task 8: 录音界面（RecorderView + 波形 + 实时转写）

**Files:**
- Create: `Features/Recorder/RecorderView.swift`
- Create: `Features/Recorder/WaveformView.swift`
- Create: `Features/Recorder/LiveTranscriptView.swift`

本任务为 UI（无单测），验证 = 构建通过 + Task 10 手动验证。

- [ ] **Step 1: 实现 WaveformView**

`Features/Recorder/WaveformView.swift`:

```swift
import SwiftUI

/// 电平波形：按当前电平渲染竖条，时间驱动的确定性动画。
struct WaveformView: View {
    let level: Float

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.08)) { context in
            HStack(alignment: .center, spacing: 3) {
                ForEach(0..<24, id: \.self) { index in
                    Capsule()
                        .fill(AppTheme.accent)
                        .frame(width: 3, height: barHeight(index: index, time: context.date))
                }
            }
            .frame(height: 52)
        }
    }

    private func barHeight(index: Int, time: Date) -> CGFloat {
        let base = 6 + CGFloat((index * 7) % 13)
        let pulse = CGFloat(level) * 34
        let phase = CGFloat((Int(time.timeIntervalSinceReferenceDate * 12) + index * 3) % 8) / 8
        return base + pulse * phase
    }
}
```

- [ ] **Step 2: 实现 LiveTranscriptView**

`Features/Recorder/LiveTranscriptView.swift`:

```swift
import SwiftUI
import FlashNoteCore

/// 实时转写面板：定稿段落列表 + 当前局部文本高亮。
struct LiveTranscriptView: View {
    let segments: [TranscriptSegment]
    let partialText: String?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(segments) { segment in
                        Text(segment.text)
                            .font(.callout)
                            .foregroundStyle(AppTheme.primaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(segment.id)
                    }
                    if let partialText, !partialText.isEmpty {
                        Text(partialText)
                            .font(.callout.weight(.medium))
                            .foregroundStyle(AppTheme.accent)
                            .padding(10)
                            .background(AppTheme.infoBackground, in: RoundedRectangle(cornerRadius: 8))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id("partial")
                    }
                }
                .padding(12)
            }
            .onChange(of: segments.count) { _, _ in
                withAnimation { proxy.scrollTo(segments.last?.id, anchor: .bottom) }
            }
            .onChange(of: partialText) { _, _ in
                withAnimation { proxy.scrollTo("partial", anchor: .bottom) }
            }
        }
        .background(AppTheme.background.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
```

- [ ] **Step 3: 实现 RecorderView**

`Features/Recorder/RecorderView.swift`:

```swift
import SwiftUI
import FlashNoteCore

/// 录音界面：REC 指示 + 计时 + 波形 + 实时转写 + 暂停/停止/完成。
struct RecorderView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appEnvironment) private var environment
    @State private var viewModel: RecorderViewModel?

    var body: some View {
        Group {
            if let viewModel {
                content(viewModel)
            } else {
                ProgressView("准备录音…")
            }
        }
        .frame(minWidth: 560, minHeight: 480)
        .task {
            // 视图层负责授权检查
            if let authError = await SpeechAuthorization.requestPermissions() {
                // 授权失败：退出录音并提示
                showAuthError(authError)
                return
            }
            viewModel = makeViewModel()
        }
    }

    private func makeViewModel() -> RecorderViewModel {
        let env = environment
        let engine = SpeechEngine() ?? SpeechEngine(locale: Locale(identifier: "en-US"))!
        return RecorderViewModel(audio: AudioService(), engine: engine, store: env!.store)
    }

    private func content(_ vm: RecorderViewModel) -> some View {
        VStack(spacing: 20) {
            header(vm)
            WaveformView(level: vm.level)
            Text(RecorderViewModel.formatElapsed(vm.elapsed))
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(AppTheme.primaryText)
            LiveTranscriptView(segments: vm.segments, partialText: vm.partialText)
            controls(vm)
        }
        .padding(24)
    }

    private func header(_ vm: RecorderViewModel) -> some View {
        HStack {
            if vm.phase != .idle {
                Circle().fill(AppTheme.destructive).frame(width: 9, height: 9)
                Text(vm.phase == .paused ? "已暂停" : "正在录音")
                    .font(.headline)
            }
            Spacer()
            Text(vm.recordingTitle)
                .font(.subheadline)
                .foregroundStyle(AppTheme.secondaryText)
        }
    }

    private func controls(_ vm: RecorderViewModel) -> some View {
        HStack(spacing: 28) {
            if vm.phase == .recording {
                IconButton(icon: AppIcons.pause, color: AppTheme.primaryText, background: AppTheme.background) {
                    vm.pause()
                }
            } else if vm.phase == .paused {
                IconButton(icon: AppIcons.play, color: .white, background: AppTheme.accent) {
                    vm.resume()
                }
            }
            IconButton(icon: AppIcons.stop, color: .white, background: AppTheme.destructive, size: 52) {
                vm.stop()
                dismiss()
            }
            IconButton(icon: AppIcons.checkmark, color: .white, background: AppTheme.accent) {
                vm.stop()
                dismiss()
            }
        }
        .padding(.top, 4)
    }

    private func showAuthError(_ error: TranscriptionError) {
        // M1：直接退出；后续里程碑做引导页
        dismiss()
    }
}

/// 圆形图标按钮。
struct IconButton: View {
    let icon: String
    var color: Color = .white
    var background: Color = AppTheme.accent
    var size: CGFloat = 46
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size * 0.38, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: size, height: size)
                .background(background, in: Circle())
                .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
        }
        .buttonStyle(.plain)
    }
}
```

注意：`SpeechEngine() ?? SpeechEngine(locale: Locale(identifier: "en-US"))!` 是兜底（zh-CN 识别器不可用时降级英文）；M2 里程碑改为设置项。

- [ ] **Step 4: 构建验证双 target**

```bash
xcodebuild -project FlashNote.xcodeproj -scheme FlashNote -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -1
xcodebuild -project FlashNote.xcodeproj -scheme FlashNoteMac -destination 'platform=macOS' build 2>&1 | tail -1
```
Expected: 均 `BUILD SUCCEEDED`。

- [ ] **Step 5: 提交**

```bash
git add Features && git commit -m "feat: add recorder UI (waveform, live transcript, controls)"
```

---

### Task 9: 录音列表与详情

**Files:**
- Create: `Features/Recordings/RecordingListView.swift`
- Create: `Features/Recordings/RecordingRow.swift`
- Create: `Features/Detail/RecordingDetailView.swift`
- Modify: `App/RootView.swift`（接入真实内容）

- [ ] **Step 1: 实现 RecordingRow**

`Features/Recordings/RecordingRow.swift`:

```swift
import SwiftUI
import FlashNoteCore

struct RecordingRow: View {
    let recording: Recording

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(recording.title)
                    .font(.headline)
                    .foregroundStyle(AppTheme.primaryText)
                    .lineLimit(1)
                Spacer()
                RecordingStatusView(status: recording.status)
            }
            HStack(spacing: 12) {
                Label(recording.createdAt.formatted(date: .abbreviated, time: .shortened), systemImage: AppIcons.clock)
                Text(Self.durationText(recording.duration))
            }
            .font(.caption)
            .foregroundStyle(AppTheme.secondaryText)
        }
        .padding(.vertical, 4)
    }

    static func durationText(_ duration: TimeInterval) -> String {
        let total = Int(duration)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
```

- [ ] **Step 2: 实现 RecordingListView**

注意：核心包 `Recording` 不可哈希，iOS 导航用 `UUID` 值路由（`NavigationLink(value: recording.id)` + `navigationDestination(for: UUID.self)`）。

`Features/Recordings/RecordingListView.swift`:

```swift
import SwiftUI
import FlashNoteCore

/// 录音列表（macOS 中栏 / iPhone 录音页）。
struct RecordingListView: View {
    @Environment(\.appEnvironment) private var environment
    @State private var recordings: [Recording] = []
    @State private var showingRecorder = false
    @State private var selectedID: UUID?

    var body: some View {
        Group {
            if recordings.isEmpty {
                ContentUnavailableView("还没有录音", systemImage: AppIcons.mic,
                                       description: Text("点击 + 开始第一次录音"))
            } else {
                List(selection: $selectedID) {
                    ForEach(recordings) { recording in
#if os(iOS)
                        NavigationLink(value: recording.id) {
                            RecordingRow(recording: recording)
                        }
#else
                        RecordingRow(recording: recording)
                            .tag(recording.id)
#endif
                    }
                }
            }
        }
        .navigationTitle("录音")
        .toolbar {
            ToolbarItem {
                Button {
                    showingRecorder = true
                } label: {
                    Image(systemName: AppIcons.plus)
                }
            }
        }
        .sheet(isPresented: $showingRecorder) {
            RecorderView()
        }
        .onAppear { reload() }
        .onChange(of: showingRecorder) { _, isShown in
            if !isShown { reload() }
        }
    }

    private func reload() {
        recordings = (try? environment?.store.fetchRecordings()) ?? []
    }
}
```

- [ ] **Step 3: 实现 RecordingDetailView**

`Features/Detail/RecordingDetailView.swift`:

```swift
import SwiftUI
import FlashNoteCore

/// 录音详情。M1：全文转写页签可用；AI 纪要 / 播放为占位（M3 实现）。
struct RecordingDetailView: View {
    let recording: Recording
    @Environment(\.appEnvironment) private var environment
    @State private var transcript: Transcript?
    @State private var selectedTab: Tab = .transcript

    enum Tab: String, CaseIterable, Identifiable {
        case transcript = "全文转写"
        case minutes = "AI 纪要"
        case player = "播放"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(recording.title)
                .font(.title2.bold())
            HStack(spacing: 12) {
                Text(recording.createdAt.formatted(date: .abbreviated, time: .shortened))
                Text(RecordingRow.durationText(recording.duration))
                RecordingStatusView(status: recording.status)
            }
            .font(.caption)
            .foregroundStyle(AppTheme.secondaryText)

            Picker("页签", selection: $selectedTab) {
                ForEach(Tab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)

            content
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task { loadTranscript() }
    }

    @ViewBuilder
    private var content: some View {
        switch selectedTab {
        case .transcript:
            if let transcript {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(transcript.segments) { segment in
                            Text(segment.text)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(12)
                }
                .background(AppTheme.background.opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                ContentUnavailableView("暂无转写", systemImage: AppIcons.document)
            }
        case .minutes:
            ContentUnavailableView("AI 纪要将在 M3 实现", systemImage: AppIcons.sparkle)
        case .player:
            ContentUnavailableView("播放器将在 M2 实现", systemImage: AppIcons.play)
        }
    }

    private func loadTranscript() {
        transcript = try? environment?.store.fetchTranscript(recordingID: recording.id)
    }
}
```

- [ ] **Step 4: 接入 RootView**

注意：iOS 侧用 `navigationDestination(for: UUID.self)` 配合列表里的 `NavigationLink(value: recording.id)`（核心包 `Recording` 不可哈希）。

`App/RootView.swift`（整体替换）：

```swift
import SwiftUI
import FlashNoteCore

struct RootView: View {
    @Environment(\.appEnvironment) private var environment
    @State private var recordings: [Recording] = []
    @State private var selection: UUID?
    @State private var showingRecorder = false

    var body: some View {
#if os(macOS)
        NavigationSplitView {
            List {
                Label("所有录音", systemImage: AppIcons.mic)
                    .fontWeight(.semibold)
                    .foregroundStyle(AppTheme.accent)
                Label("工作", systemImage: AppIcons.folder)
                Label("课程", systemImage: AppIcons.book)
                Label("会议", systemImage: AppIcons.chat)
            }
            .navigationTitle("FlashNote")
            .listStyle(.sidebar)
        } content: {
            RecordingListView()
        } detail: {
            if let selection,
               let recording = recordings.first(where: { $0.id == selection }) {
                RecordingDetailView(recording: recording)
                    .id(recording.id)
            } else {
                ContentUnavailableView("选择一条录音", systemImage: AppIcons.document)
            }
        }
        .frame(minWidth: 1000, minHeight: 620)
        .onChange(of: selection) { _, _ in reloadRecordings() }
#else
        TabView {
            NavigationStack {
                RecordingListView()
                    .navigationDestination(for: UUID.self) { id in
                        if let recording = recordings.first(where: { $0.id == id }) {
                            RecordingDetailView(recording: recording)
                        }
                    }
            }
            .tabItem { Label("录音", systemImage: AppIcons.mic) }
            ContentUnavailableView("文件夹将在 M4 实现", systemImage: AppIcons.folder)
                .tabItem { Label("文件夹", systemImage: AppIcons.folder) }
            ContentUnavailableView("设置将在 M3 实现", systemImage: AppIcons.settings)
                .tabItem { Label("设置", systemImage: AppIcons.settings) }
        }
#endif
    }

    private func reloadRecordings() {
        recordings = (try? environment?.store.fetchRecordings()) ?? []
    }
}
```

- [ ] **Step 5: 构建验证双 target**

```bash
xcodebuild -project FlashNote.xcodeproj -scheme FlashNote -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -1
xcodebuild -project FlashNote.xcodeproj -scheme FlashNoteMac -destination 'platform=macOS' build 2>&1 | tail -1
```
Expected: 均 `BUILD SUCCEEDED`。

- [ ] **Step 6: 提交**

```bash
git add Features App && git commit -m "feat: add recording list and detail views"
```

---

### Task 10: 端到端验证与 README

**Files:**
- Create: `README.md`（仓库根，补充 App 使用说明——若已存在则合并）
- Modify: 按验证清单修复发现的问题

- [ ] **Step 1: 全量测试**

```bash
xcodebuild -project FlashNote.xcodeproj -scheme FlashNote -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test 2>&1 | tail -3
xcodebuild -project FlashNote.xcodeproj -scheme FlashNoteMac -destination 'platform=macOS' test 2>&1 | tail -3
```
Expected: 双平台测试全部通过（iOS 模拟器上 Speech 授权测试可能被环境限制——若 `SpeechAuthorizationTests` 在模拟器失败，检查是否因授权弹窗；macOS 测试必须全绿）。

- [ ] **Step 2: macOS 真机手动验证（清单）**

构建并启动 macOS App：

```bash
xcodebuild -project FlashNote.xcodeproj -scheme FlashNoteMac -destination 'platform=macOS' build
open "$(xcodebuild -project FlashNote.xcodeproj -scheme FlashNoteMac -showBuildSettings 2>/dev/null | awk '/ BUILT_PRODUCTS_DIR/{print $3}')/FlashNoteMac.app"
```

逐项验证：
1. 首次启动弹出麦克风 + 语音识别授权；拒绝后无崩溃。
2. 点「+」进入录音界面；REC 红点、计时递增、波形随音量跳动。
3. 对着麦克风说话，实时转写逐句出现；最新一句蓝色高亮。
4. 暂停 → 计时停、状态变「已暂停」；继续 → 恢复。
5. 停止/完成 → 回到列表，出现新录音，状态徽章「已转写」。
6. 点击录音进入详情，「全文转写」页签显示完整内容。
7. 再次录音并停止，列表按时间倒序排列。
8. 关闭并重开 App，录音仍在（本地持久化）。

发现的问题在本任务内修复并重新提交（构建 → 手动验证 → commit 循环）。

- [ ] **Step 3: 写仓库 README**

`README.md`（仓库根）：

```markdown
# FlashNote

录音 + 实时转写 + AI 纪要（macOS / iOS）。

## 结构

- `FlashNoteCore/` — 纯 Swift 核心层（模型 / 转写协议 / LLM 客户端 / 纪要生成 / 存储协议）
- `App/` `Features/` `Services/` `DesignSystem/` — SwiftUI 应用层
- `docs/superpowers/` — 设计规格与实施计划

## 构建

```bash
xcodegen generate          # 生成 FlashNote.xcodeproj
open FlashNote.xcodeproj   # 或命令行 xcodebuild
```

核心层测试：`cd FlashNoteCore && swift test`
App 测试：`xcodebuild -project FlashNote.xcodeproj -scheme FlashNoteMac -destination 'platform=macOS' test`

## 当前进度

- M1 完成：工程骨架、录音、Apple Speech 实时转写、本地保存、列表/详情
- M2+：导入转写、AI 纪要、iCloud 同步、搜索（见设计规格 §9）
```

- [ ] **Step 4: 提交**

```bash
git add README.md && git commit -m "docs: app README with build and verification instructions"
```

---

## 自检结果（计划作者已执行）

**1. Spec 覆盖（对照设计规格）：**
- §5.1 直接录音 + 实时转写 → Task 5/6/7/8 ✓（暂停/继续/停止；实时滚动）
- §4.2 音频文件本地缓存（`{recordingID}.caf`）→ Task 7 ✓
- §4.3 设置（转写通道）→ M2 设置页（本计划仅默认 Speech）
- §7 权限拒绝 → Task 4 映射 + RecorderView 引导（M1 简化退出）✓
- UI（录音界面/列表/详情）→ Task 8/9 ✓（对齐已确认的 mockup：专业蓝、状态徽章、实时高亮）

**2. 占位符扫描：** 无 TBD；每个代码步骤含完整代码。Task 7 的授权同步问题已内联修正（授权移至视图层）。

**3. 类型一致性：**
- `TranscriptionService(recordingID:engine:)`、`TranscriptSegment(startTime:text:isFinal:)`、`Recording(id:title:duration:audioFilename:)`、`markTranscribed()`、`FileRecordingStore(root:)`、`RecordingStore` 协议方法 —— 全部来自已合并的核心包 API。
- `TranscriptionError`（Equatable）用于 `#expect(==)` 断言 ✓。
- 测试文件需 `import FlashNoteCore`（@testable 不传递依赖）——Task 4/7 已注明。
- `Recording` 不可哈希 → iOS 导航用 `UUID` 值路由（Task 9 修正段）✓。

**4. 已知取舍：**
- `SpeechEngine.init?` 在 zh-CN 识别器不可用时返回 nil，RecorderView 降级英文（M2 改为设置项）。
- 模拟器无麦克风：iOS 目标只验证构建与逻辑测试；真机录音验证在 macOS target。
- `awaitSpeechAuthorization` 曾计划信号量同步包装，已改由视图层 async 调用（避免测试死锁）。
- 波形为电平驱动动画（非真实频谱）；波形文件写入为 PCM .caf（Whisper/播放兼容性 M2 验证）。
- 详情页「AI 纪要」「播放」为占位（M3/M2）。
