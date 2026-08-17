# FlashNote 设计文档

- 日期：2026-08-17
- 状态：已与用户逐节确认（技术路线、转写方案、LLM 接入、同步、组织方式、纪要风格、视觉设计、Logo）

## 1. 项目概述

FlashNote 是一款面向 **macOS 与 iOS** 的录音 + 实时转写 + AI 纪要应用。用户可以直接录音，也可以导入已有音频；获得完整转写文本，并让 AI 按可选风格（工作纪要、会议纪要、课程纪要、自定义模板）生成纪要。所有数据通过 iCloud 在 Mac 与 iPhone 间自动同步。

### 1.1 核心需求

1. **录音**：直接录音（麦克风），支持暂停/继续/停止。
2. **实时转写**：录音过程中转写文本实时滚动显示。
3. **导入音频**：导入本地音频文件（m4a / wav / mp3 / caf 等）并转写。
4. **全文转写**：生成并查看完整转写（带时间戳、说话人标注）。
5. **AI 纪要**：基于转写生成纪要；纪要风格可切换（工作纪要 / 会议纪要 / 课程纪要 / 自定义模板），切换后一键重新生成。
6. **自接模型**：LLM 层统一走 OpenAI 兼容 API（Base URL + API Key + 模型名），可接 DeepSeek、OpenAI、通义千问、Moonshot、Ollama 本地等。
7. **多端同步**：iCloud 同步（CloudKit 存结构化数据，iCloud Drive 存音频文件）。
8. **内容组织**：文件夹 + 全文搜索。

### 1.2 非目标（YAGNI）

- 不做账号体系、不做自建服务器。
- 不做跨平台（仅苹果生态）。
- 不做笔记软件级别的双向链接、Markdown 编辑器。
- 不做说话人分离的自动识别（转写按段落标注，说话人标记为手动/占位能力，V1 不承诺自动区分说话人）。

## 2. 技术路线

- **语言/框架**：Swift + SwiftUI，单一代码库同时构建 iOS App 与 macOS App。
- **最低系统版本**：iOS 17.0 / macOS 14.0（Sonoma），充分利用 SwiftData 可选、`.onChange` 双参数等新特性，同时保证可用性。
- **工程结构**：Xcode 工程 + Swift Package 分层（Core / Features / DesignSystem / Shared）。
- **实时转写**：Apple Speech 框架（`SFSpeechRecognizer` 流式识别）。
- **离线长音频转写**：whisper.cpp（或 WhisperKit）本地模型。
- **云端转写（可选）**：用户自配 Key 的 OpenAI Whisper API / Deepgram 等。
- **AI 纪要**：OpenAI 兼容 Chat Completions 协议。
- **同步**：CloudKit（记录、转写、纪要、文件夹、模板）+ iCloud Drive（音频文件）。
- **搜索**：本地全文索引（转写文本与纪要文本），用 Core Spotlight 提供系统级搜索（可选增强）。

## 3. 系统架构

五层结构，层间通过协议/接口解耦：

```
① SwiftUI 应用层（iOS + macOS 共用）
   录音界面 / 实时转写 / 转写+纪要详情 / 文件夹列表 / 设置
        │
② 服务层 Services（领域逻辑，与 UI 解耦）
   AudioService · TranscriptionService · AIService · SyncService
        │
③ 转写引擎（可插拔）
   Apple Speech（实时、离线、免费）
   whisper.cpp 本地模型（导入长音频、离线）
   云端 ASR API（可选、用户自配 Key）
        │
④ LLM 层（OpenAI 兼容 API，用户自配）
   纪要生成（风格模板驱动）· 转写矫正（可选）
        │
⑤ 存储层
   CloudKit（结构化数据） + iCloud Drive（音频文件）
   本地缓存降级（iCloud 不可用时的本地 SQLite/文件）
```

### 3.1 关键接口

- `TranscriptionEngine` 协议：`start/appendAudio/pause/stop`、`onSegment(_:)`、`isRealtime`。三个实现：`SpeechEngine`（实时）、`WhisperEngine`（整段）、`CloudASREngine`（实时或整段，取决于后端能力）。
  - **已实现决策（核心包 v0.1）**：核心协议保持最小化 `start()/cancel()` + `onSegment/onError` 回调；**音频采集与暂停由各引擎实现自行负责**（如 Speech 引擎内联 AVAudioEngine 采集，暂停即暂停采集）。App 阶段如需优雅停止（区别于取消），以协议扩展默认实现补 `stop()`；不向核心塞入 `appendAudio`（音频不经过核心层）。
  - **App 阶段待补**：实时转写 UI 需要直播观察通道——`TranscriptionService` 需暴露 `onNewSegment` 回调（或 AsyncStream），供"最新一段高亮/滚动"使用；当前核心只有快照轮询。
- `LLMClient`：`complete(prompt:messages:) -> AsyncThrowingStream<String, Error>`，封装 OpenAI 兼容协议，支持流式与非流式。
- `MinutesGenerator`：输入转写文本 + `MinutesTemplate`，输出结构化纪要。当前用非流式 `complete()`；App 阶段纪要流式展示可走 `LLMClient.stream`。
- `RecordingStore`：统一的数据访问层，内部决定走 CloudKit 还是本地降级。核心 v0.1 为同步签名；CloudKit 实现需桥接异步或届时评估协议改造。

## 4. 数据模型

### 4.1 CloudKit 记录（结构化数据）

| 实体 | 字段 |
|---|---|
| `Recording` | id, title, folderID, audioFilename, audioAssetID, duration, createdAt, updatedAt, status（recording / transcribed / summarized）, transcriptID, minutesID, engineUsed |
| `Transcript` | id, recordingID, segments: [Segment], fullText, language, createdAt |
| `TranscriptSegment` | startTime, endTime, speaker（可选）, text, isFinal |
| `Minutes` | id, recordingID, style, templateID, content（结构化 JSON）, model, promptVersion, generatedAt |
| `Folder` | id, name, parentID, colorIndex, createdAt |
| `MinutesTemplate` | id, name, isBuiltin, sections（期望小节标题）, systemPrompt, userPromptTemplate（含 {transcript} 占位符） |

### 4.2 音频文件

- 存入 iCloud Drive 应用容器（`iCloud.com.flashnote.app/audio/`），文件名 `{recordingID}.m4a`。
- 本地缓存策略：录音时先写本地，停止后异步上传 iCloud Drive；播放时优先本地缓存，缺失时按需下载。

### 4.3 设置

- LLM：baseURL、apiKey（存 Keychain）、model、temperature。
- 转写：默认通道（实时：Speech；导入：Whisper）、云端 ASR 配置（可选）。
- 纪要：默认风格、自定义模板列表（随 CloudKit 同步）。
- 通过 `UserDefaults` + Keychain 保存本地，模板与偏好经 CloudKit 同步。

## 5. 核心流程

### 5.1 直接录音 + 实时转写

1. 请求麦克风与语音识别权限（`AVAudioApplication` / `SFSpeechRecognizer`）。
2. `AudioService` 用 `AVAudioEngine` 采集，写入本地文件。
3. `SpeechEngine` 流式识别，回调段落 → `TranscriptionService` 追加到 `Transcript`（最新一段高亮）。
4. 暂停/继续：暂停引擎并保留缓冲；停止：结束识别，落盘。
5. 停止后：转录状态 → transcribed；若配置了"完成后自动生成纪要"，进入 5.4。

### 5.2 导入音频

1. 文件选择器（UTType：audio），复制到应用容器。
2. 选择转写通道（默认 Whisper；可切云端）。
3. `WhisperEngine` / `CloudASREngine` 整段处理，进度条展示；完成后生成 `Transcript`。

### 5.3 全文转写

- 详情页「全文转写」页签：按时间戳分段展示，说话人标注（V1 支持手动改名，自动分离列为后续增强）。
- 支持编辑文本、复制、分享（导出 txt / markdown）。

### 5.4 AI 纪要生成

1. 用户选择风格（内置：工作纪要 / 会议纪要 / 课程纪要；或自定义模板）。
2. `MinutesGenerator` 按模板组装 prompt（含转写全文或分段摘要策略——长文本自动分段/摘要后再生成，控制 token）。
3. 调 `LLMClient` 流式生成，写入 `Minutes`。
4. 切换风格 → 保留旧纪要（可回溯），用新模板重新生成。
5. 纪要内容结构化 JSON（结论 / 行动项 / 待跟进 等），UI 渲染为卡片。

### 5.5 全文搜索

1. 搜索入口：macOS 列表栏搜索框 / iPhone 录音页搜索框。
2. 索引范围：录音标题、转写全文、纪要文本；本地索引随记录更新增量维护。
3. 命中结果按录音聚合展示，点击直达详情对应页签；高亮命中片段。
4. 可选增强：Core Spotlight 索引，支持系统级搜索。

### 5.6 同步

- 记录级操作经 CloudKit `CKRecordZone`；音频为 `CKAsset` + iCloud Drive。
- 冲突策略：本地优先，`updatedAt` 合并；纪要/转写以新为准，旧版本保留为历史。

## 6. 视觉设计（已确认）

- **设计语言**：专业蓝（accent `#0a84ff`），白底浅灰卡（`#f5f5f7` / `#fafafa`），圆角卡片 + 柔和阴影，全线性 SVG 图标（1.8 线宽、圆角端点）。
- **Logo**：靛紫渐变圆角方形（`#3b6ef6 → #6d5df6`）+ 白色对话气泡 + 深靛内芯（`#2b2b7a`）+ 白色声波柱。
- **macOS**：三栏布局（文件夹 / 录音列表 / 详情）。
- **iPhone**：标签栏（录音 / 文件夹 / 设置）。
- **录音界面**：REC 脉冲红点 + 大字计时 + 动态波形 + 实时转写滚动 + 暂停/停止/完成三键 + 引擎标签。
- **详情界面**：页签（AI 纪要 / 全文转写 / 播放）；AI 纪要含风格切换条与重新生成按钮；转写按说话人分段。
- Mockup 存档：`.superpowers/brainstorm/`（architecture / navigation-v2 / logo-final / recording / detail）。

## 7. 错误处理

| 场景 | 处理 |
|---|---|
| 麦克风/语音识别权限拒绝 | 引导页说明用途 + 跳转系统设置 |
| 无网络 | 实时转写自动降级离线 Speech；LLM 纪要失败提示重试（不阻塞转写） |
| LLM API 错误 | 401（Key 无效）、429（限流）、超时 → 明确提示与重试按钮；支持切换模型 |
| iCloud 不可用 | 自动降级本地存储并提示；恢复后增量同步 |
| 长音频内存压力 | 导入转写分段处理；UI 转写视图懒加载 |
| 录音中断（来电等） | 自动暂停并提示恢复 |

## 8. 测试策略

- **单元测试**：`TranscriptionEngine` 协议（mock 引擎）、`MinutesGenerator`（模板渲染与长文本分段）、`LLMClient`（请求构造、流式解析、错误映射）、`RecordingStore`（CRUD 与降级路径）。
- **集成测试**：CloudKit 本地开发容器；iCloud Drive 上传下载。
- **UI 测试（XCUITest）**：录音→停止→纪要主流程；导入→转写；风格切换。
- **手动验证矩阵**：iPhone + Mac 双端同步；离线/在线；模拟器 + 真机（麦克风、Speech 需真机）。

## 9. 里程碑

- **M1 骨架与实时转写**：工程搭建、设计系统、录音 + Speech 实时转写 + 本地保存。
- **M2 导入与全文**：文件导入 + Whisper 转写 + 全文转写视图 + 播放。
- **M3 AI 纪要**：LLMClient（OpenAI 兼容）+ 内置三风格模板 + 自定义模板 + 风格切换重生成。
- **M4 同步与组织**：CloudKit + iCloud Drive 同步、文件夹、全文搜索。
- **M5 打磨与发布**：Logo/图标/空状态、错误处理完善、测试补齐、App 上架准备。
