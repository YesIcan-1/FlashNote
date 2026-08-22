# FlashNote 设计文档 V2（AI 录音硬件集成版）

- 日期：2026-08-18（V1 为 2026-08-17，本版因接入 QS668/CB08 硬件与新增 AI 功能重写）
- 状态：已与用户确认（BLE 连接 · 自接模型为主 · 分阶段先硬件后 AI · 支持多语言翻译）
- 硬件：NextProto **AI 录音卡**（型号 QS668 / 广播名 CB08），BLE 控制

## 1. 项目概述

FlashNote 是 **macOS + iOS 的 AI 录音生产力平台**：通过蓝牙（BLE）连接用户购买的 QS668 AI 录音卡，录音并实时转写、导入音频转写，然后**一次转写产出多种 AI 价值**——摘要/纪要、思维导图、知识库问答、可视化报告、深度研究、播客生成、多语言翻译与语言支持。模型全部走用户的 OpenAI 兼容配置（可接 DeepSeek/OpenAI/通义/Ollama 等）。

### 1.1 核心需求

1. **硬件连接（BLE）**：扫描/连接 QS668 录音卡，读取设备信息（电量/容量/固件/授权码）、文件列表、下载音频、实时推流转写、远端录音控制、增益。
2. **实时转写**：录音过程中转写分句分行、带时间戳；硬件实时 OPUS 码流 → 解码 → 分段 ASR。
3. **导入音频**：导入本地音频（m4a/wav/mp3/caf）或从设备下载 → 转写。
4. **全文转写**：分句 + 时间戳 +（后续）说话人标注。
5. **AI 产出工厂**：一次转写生成多种产出（自接模型）：
   - 摘要 / 会议纪要（模板：工作/会议/课程/自定义）
   - 思维导图（层级结构 → 画布渲染）
   - 知识库问答（转写入库 RAG → 聊天）
   - 可视化报告（结构化数据 → 图表）
   - 深度研究 / 拓展（多步 LLM）
   - 播客生成（LLM 脚本 + TTS）
   - 多语言翻译与语言支持
6. **多端同步**：iCloud（CloudKit 结构化数据 + iCloud Drive 音频；转写纯文本本地 + 向量库）。
7. **内容组织**：文件夹 + 全文搜索 +（后续）声纹说话人分离。

### 1.2 非目标（YAGNI）

- 不做账号体系、自建服务器（自接模型即可）。
- 说话人自动分离（声纹识别）为 Phase C，非当前 V1。
- 不做笔记软件级双向链接；播客 TTS 优先本地 Speech（可选云端）。

## 2. 硬件接口（QS668 AI 录音卡，BLE）

- **GATT**：Service `0xAE20`；AE21 写（无应答）、AE22 通知（控制/音频/列表/文件）、AE23 通知（按键/录音状态）。连接后先订阅 AE22，AE22/AE23 用独立流式解析缓存。
- **帧**（通用）：`[0x5A][SEQ][CRC:2B LE][LEN:2B LE][DATA=TYPE+CMD+PARAMS]`；CRC-16/XMODEM（多项式 0x1021，初值 0，LEN 原始字节 + DATA）。
- **命令类型**：TYPE0 控制（时间/容量/电量/固件/授权码）；TYPE1 实时音频（开始/音频码流/停止/暂停继续/状态）；TYPE2 文件（列表/导入/数据/结束/删除/终止/分段）；TYPE3 按键/录音控制（开始/保存/暂停/继续/状态/时长/文件名/增益）。
- **实时音频码流**：固定 **40 字节/包** 的原始 OPUS（Opus config 9，每包 20ms，采样率 16kHz）。App 侧需**解码为 PCM**（libopus 或 AudioToolbox）后喂 ASR。
- **下载**：文件列表（CM 2-1，大端 count/time/size + name 20B）；下载命令 2-2 完整帧 36B **必须一次 GATT 写入**；候选名 `base.wav → base.opus → 原始截断名`；支持分段与断点续传；结束码 0/1/2/3。
- 协议实现参考：厂商资料页（物流单号获取）与 `github.com/lomehong/record`（含 Python 实现与 OPUS→OGG 包装脚本）。

## 3. 系统架构（五层）

```
① 硬件层（BLE / CoreBluetooth）
   CB08Central(scan/connect) · CB08Protocol(帧/CRC/SEQ) · CB08Device(设备信息/列表/下载/实时/录音控制)
        │ 音频文件(WAV/OPUS) · 实时 OPUS 码流(40B/包)
② 音频/转写层
   OpusDecoder(40B包→PCM) · AppleSpeechEngine(实时,含硬件流) · CloudWhisperEngine(文件) ·
   WhisperKitEngine(本地,顺延) · 多语言选择
        │ 转写全文（分句 + 时间戳 + 说话人占位）
③ AI 产出工厂（自接 OpenAI 兼容模型）
   SummaryGenerator(摘要/纪要) · MindMapGenerator · RAGKnowledgeBase · ReportGenerator ·
   DeepResearch · PodcastGenerator(脚本+TTS) · TranslationService · 语言调度
        │ 结构化产出（JSON/Markdown）
④ 渲染层
   思维导图画布 · 图表报告 · 知识库聊天 · 播客播放器 · 纪要卡片 · 硬件设备面板
        │
⑤ 存储/同步
   CloudKit + iCloud Drive + 本地文件 + 向量库(embedding) + 设备状态缓存
```

### 3.1 关键接口

- `CB08Device`：`connect/disconnect`、`battery()`、`fileList()`、`download(file:progress:)`、`startRealtimeStream(onAudio:onState:)`、`recordStart/pause/resume/save`、`setGain`。
- `OpusDecoder`：`decode(packets: Data) -> [AVAudioPCMBuffer]`。
- `AIOutputFactory`：`func generate(kind: OutputKind, transcript: Transcript, options: OutputOptions) async throws -> AIOutput`，`OutputKind = summary|mindmap|qa|report|deepResearch|podcast|translation`。
- `RAGKnowledgeBase`：embedding 入库 + 检索 + 生成回答。

## 4. 数据模型（扩展核心层）

沿用 V1 的 `Recording/Transcript/TranscriptSegment/Folder/Minutes/MinutesTemplate`，新增：
- `DeviceRecording`：deviceID, deviceFile, remotePath, downloadedAt。
- `AIOutput`：id, recordingID, kind, content(JSON), model, promptVersion, createdAt。
- `KBChunk`：id, recordingID, text, embedding(Data), sourceRange。
- `Podcast`：id, recordingID, script, audioFilename, ttsEngine。

## 5. 核心流程

5.1 **连接硬件**：扫描 → 连接(0xAE20, 订阅 AE22/AE23) → 读取设备信息 → 同步时间。
5.2 **下载并转写**：fileList → 选择 → download(WAV) → CloudWhisper/WhisperKit 转写 → 保存 Transcript + AIOutput。
5.3 **实时硬件转写**：startRealtimeStream → 订阅 40B OPUS 包 → OpusDecoder → 分段喂 Apple Speech / 流式 ASR → 分句转写。
5.4 **录音控制**：远端开始/保存/暂停/继续，状态/时长查询，增益。
5.5 **AI 产出**：转写 → OutputFactory 按 kind 生成（LLM），结构化入库。
5.6 **知识库问答**：转写分块 → embedding → 入库；提问 → 检索 → LLM 回答。
5.7 **同步**：CloudKit + iCloud Drive；向量库本地增量。

## 6. 里程碑（重排）

- **Phase A（硬件 BLE）**：工程扩展、CB08 BLE 协议/设备层、文件列表/下载、实时 OPUS 解码 + 转写、录音控制、设备面板 UI。
- **Phase B（AI 产出）**：摘要/纪要增强 · 思维导图 · 知识库问答 · 可视化报告 · 深度研究 · 播客 · 多语言翻译。
- **Phase C（声纹/说话人分离）**：diarization（音频级，自接/云端）。
- **Phase D（打磨发布）**：图标、空状态、错误恢复、上架。

## 7. 错误处理

- 蓝牙不可用/断开：重连提示；下载中断：断点续传；实时流中断：自动重连。
- OPUS 解码失败：丢弃坏包计数重同步。
- 转写/LLM 失败：明确错误 + 重试；模型不可用降级提示。
- iCloud 不可用：本地降级。

## 8. 测试策略

- 硬件协议层：帧/CRC 构造解析、文件列表解码、下载会话（模拟传输）、OPUS 包装（对照厂商脚本向量）。
- AI 层：各 Generator 单测（mock LLM）、RAG 检索、翻译。
- UI 测试：设备面板、下载进度、实时转写、AI 产出展示。
- 手动矩阵：真机（QS668 蓝牙）连接/下载/实时转写/录音控制。

## 9. 已知取舍

- OPUS 解码用 libopus 绑定或 AudioToolbox（OS 无原生 OGG/Opus）；实时流按 40B 包分批。
- 说话人分离（声纹）为 Phase C，数据已带时间戳。
- 播客 TTS 优先本地 `AVSpeechSynthesizer`（可选云端 ElevenLabs）。
- 硬件"多语言翻译"在 App 侧实现（设备只采集）。
