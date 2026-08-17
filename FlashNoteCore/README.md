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
