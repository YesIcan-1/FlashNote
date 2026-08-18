# FlashNote

录音 + 实时转写 + AI 纪要（macOS / iOS）。

## 结构

- `FlashNoteCore/` — 纯 Swift 核心层（模型 / 转写协议 / LLM 客户端 / 纪要生成 / 存储协议），可用 `swift test` 独立测试
- `App/` `Features/` `Services/` `DesignSystem/` — SwiftUI 应用层（双平台共享源码，条件编译入口）
- `docs/superpowers/` — 设计规格与实施计划

## 构建

```bash
xcodegen generate          # 生成 FlashNote.xcodeproj（已 gitignore）
open FlashNote.xcodeproj   # 或用下面的命令行
```

核心层测试：

```bash
cd FlashNoteCore && swift test
```

App 测试（macOS，Apple Silicon 需单架构）：

```bash
xcodebuild -project FlashNote.xcodeproj -scheme FlashNoteMac \
  -destination 'platform=macOS' ONLY_ACTIVE_ARCH=YES ARCHS=arm64 test
```

iOS 构建验证（免签名）：

```bash
xcodebuild -project FlashNote.xcodeproj -scheme FlashNote \
  -sdk iphoneos CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=YES ARCHS=arm64 build
```

> 说明：XcodeGen 2.46 的本地 Swift Package 引用在 Xcode 26.6 下多平台产物路径解析异常，
> 故 FlashNoteCore 以两个 framework target（iOS/macOS 变体）集成，包本体保留用于 CLI 测试。

## 当前进度

- **M1 完成**：工程骨架、直接录音（AVAudioEngine）、Apple Speech 实时转写（分句分行 + 时间戳）、本地保存、录音列表与详情
- **M2 完成**：导入音频转写（云端 Whisper API）、设置页（引擎选择 + LLM 配置）、音频播放器；本地 WhisperKit 待网络恢复后接入
- M3+：AI 纪要（LLM 接入与风格模板）、iCloud 同步、文件夹与搜索、App 图标（见设计规格 §9）

## 手动验证（macOS）

1. 构建后用 **`open`** 启动生成的 `FlashNoteMac.app`（不要从终端直接执行二进制——TCC 会把责任算到终端应用导致隐私崩溃）
2. 点「＋」→ 依次授权「语音识别」与「麦克风」→ 自动开始录音
3. 录音 → 说话 → 实时转写逐句出现 → 停止 → 列表出现"已转写"录音 → 详情查看全文
