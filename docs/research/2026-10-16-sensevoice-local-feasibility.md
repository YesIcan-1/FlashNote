# SenseVoice 作为 FlashNote 本地离线转写引擎的可行性（2026-10-16）

## 结论

**技术上可行，但应把它定义为“离线文件转写 + VAD 端点式准实时转写”，不能承诺为原生连续流式识别。** SenseVoiceSmall 是 234M 参数的非自回归 CTC 模型，官方发布的 checkpoint 支持普通话、粤语、英语、日语、韩语的 ASR/LID，并输出情感与声音事件标签；它本身不做说话人分离。官方直接推理要求单段不超过 30 秒，长音频应先做 VAD 或固定窗口切分。

对 FlashNote 的建议是：

1. **有条件 GO：做独立技术验证。** 首期只做 INT8、CPU EP、16 kHz 单声道、文件转写与 VAD 分句；复用同一原生 C/C++/Swift 边界覆盖 iOS 与 macOS。
2. **推荐实现：`sherpa-onnx` 原生 Swift/iOS 封装，模型由 FlashNote 从固定的官方 SenseVoiceSmall 权重自行导出并量化。** 这条路径已经覆盖特征提取、CTC/SentencePiece 解码、时间戳和 VAD 编排，工程风险明显低于只接 ONNX Runtime 后自己重写完整音频前后处理。
3. **当前 NO-GO：不要立即作为 Apple Speech 的“逐字实时”替代，也不要在许可澄清和实机基准之前随 App 商业分发权重。** 官方 README 表述“允许商业使用”，但其引用的澄清 issue 又明确标注尚非许可方/核心维护者最终确认；权重协议还含自动修订、行为条款和空缺的适用法域，生产发布需书面确认或法律审查。
4. **不采用本机 FastAPI/Python/HTTP。** 它适合 macOS 开发机或自管服务器，不是 iOS 的受支持推理形态，也会让双平台实现、生命周期、包体和后台执行复杂化。iOS 必须把推理运行时直接链接进 App。

这不是法律意见；下面把已确认事实与工程推断分开列出。

## 1. 已确认：模型能力与边界

### 1.1 SenseVoiceSmall checkpoint 能做什么

- [SenseVoice 官方 README](https://github.com/QwenAudio/SenseVoice/blob/main/README.md#introduction)明确：已发布的 SenseVoiceSmall checkpoint 支持普通话、粤语、英语、日语、韩语的 ASR 和语言识别，并带情感与音频事件标签。论文/项目所说的“50+ 语言”是更广的研究范围，不能套到这个已发布 checkpoint 上。
- [FunASR 官方模型表](https://github.com/modelscope/FunASR/blob/main/README.md)列出 SenseVoiceSmall 为 **234M 参数**，任务是 ASR + emotion + events，语言为 zh/en/ja/ko/yue。
- 官方列出的情感标签包括 `HAPPY`、`SAD`、`ANGRY`、`NEUTRAL`、`FEARFUL`、`DISGUSTED`、`SURPRISED`；事件标签包括 `BGM`、`Speech`、`Applause`、`Laughter`、`Cry`、`Sneeze`、`Breath`、`Cough`。[标签定义](https://github.com/QwenAudio/SenseVoice/blob/main/README.md#data-prepare)
- `use_itn` 控制输出是否包含标点和逆文本归一化，例如数字、日期、百分比的书写形式；这是推理输入开关，不需要另一套模型。[参数说明](https://github.com/QwenAudio/SenseVoice/blob/main/README.md#inference)
- **VAD 不是 SenseVoiceSmall checkpoint 的输出。** 官方示例使用独立的 FSMN-VAD 将长音频切成不超过 30 秒的段。
- **说话人分离也不是 checkpoint 的输出。** 官方组合方案另加 FSMN-VAD、CAM++ 和标点模型；CAM++ 产生匿名 speaker cluster，并非身份识别。官方说明还指出该组合只在固定公开样例上跑通，未验证 diarization 准确率。[Speaker Diarization](https://github.com/QwenAudio/SenseVoice/blob/main/README.md#speaker-diarization)

### 1.2 它不是原生流式模型

- 官方直接推理接口把输入限制为 **30 秒以内**；长录音的默认方案是 FSMN-VAD 分段，或 30 秒窗口 + 2 秒重叠的有界内存脚本。[直接推理](https://github.com/QwenAudio/SenseVoice/blob/main/README.md#inference)、[无 VAD 长音频方案](https://github.com/QwenAudio/SenseVoice/blob/main/README.md#long-audio-without-vad)
- 官方 README 将 `streaming-sensevoice` 放在第三方工作中，并明确称其为截断注意力实现的“伪流式”，会牺牲一些准确率。[第三方流式说明](https://github.com/QwenAudio/SenseVoice/blob/main/README.md#remarkable-third-party-work)
- `sherpa-onnx` 文档中的 “Real-time/Streaming with VAD” 实际是 **VAD + non-streaming ASR 的 simulated streaming**：收音持续进行，但文本在语音端点或最大段长到达后定稿，而非模型维护跨 chunk 的流式状态。[SenseVoice 预训练模型说明](https://k2-fsa.github.io/sherpa/onnx/sense-voice/pretrained.html)

因此，FlashNote 可以在录音时展示“上一语音段的快速定稿”，也可周期性跑临时窗口作为 provisional text；但后者会重复计算、边界不稳定，不能把它描述成稳定逐字流式。

## 2. 已确认：体积、性能证据与未知项

| 制品 | 已确认体积 | 适用判断 |
|---|---:|---|
| 官方 PyTorch `model.pt` | 936 MB；仓库总计约 944 MB | 不适合直接放进移动 App |
| sherpa-onnx FP32 导出 | 约 894–895 MB | 移动端不建议 |
| sherpa-onnx INT8 导出 | 约 228–239 MB，另加约 308 KB tokens | 移动端 PoC 的现实起点 |
| 官方 GGUF F16 / Q8 | 约 470 MB / 254 MB | 可作为 C++/GGUF 路线对照，不是 ONNX 体积 |

来源：[官方 checkpoint 文件列表](https://huggingface.co/FunAudioLLM/SenseVoiceSmall/tree/main)、[sherpa-onnx 导出说明](https://k2-fsa.github.io/sherpa/onnx/sense-voice/export.html)、[INT8 文件](https://huggingface.co/csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17/blob/main/model.int8.onnx)、[官方 GGUF 文件列表](https://huggingface.co/FunAudioLLM/SenseVoiceSmall-GGUF/tree/main)。

性能方面能确认的是：

- 官方 README 在其特定 benchmark 中报告，相近参数量下 SenseVoiceSmall 比 Whisper-Small 快 5 倍以上、比 Whisper-Large 快 15 倍以上；这不是 Apple 设备保证。[官方 benchmark 概述](https://github.com/QwenAudio/SenseVoice/blob/main/README.md#computational-efficiency)
- sherpa-onnx 在 RK3588 上公布的 INT8 CPU RTF 为 A55 4 线程约 0.175、A76 4 线程约 0.049；它能证明 ARM CPU 实时因子有潜力小于 1，但不能外推成具体 iPhone/Mac 数字。[sherpa-onnx speed test](https://k2-fsa.github.io/sherpa/onnx/sense-voice/pretrained.html#speed-test-on-rk3588-cpu)
- ONNX Runtime 官方移动指南要求模型同时能放入磁盘和内存，并要求实测包体、延迟、功耗；对量化模型建议先从 CPU EP 开始。INT8 通常把 FP32 权重体积降至约四分之一。[ORT mobile](https://onnxruntime.ai/docs/tutorials/mobile/)

**没有找到官方 Apple 设备上的 SenseVoiceSmall 峰值内存、冷启动、RTF、能耗或热降频数据。** 228–239 MB 只是模型文件，不是进程峰值；ORT session、图优化、解量化/算子临时缓冲、声学特征和并发 buffer 都会增加内存。合理的工程推断是“INT8 总驻留会达到数百 MB”，具体数字必须用 Instruments 在目标设备上量。

建议 PoC 至少记录：冷加载时间、首段延迟、10/30 秒段 RTF、30 分钟持续录音后的 thermal state、峰值 physical footprint、前后台切换和内存警告。发布门槛可先设为：目标最低设备 RTF p95 < 0.5、30 秒段峰值内存 < 600 MB、冷加载 < 3 秒；这些是 FlashNote 的建议验收线，不是上游承诺。

## 3. 已确认：Apple 平台可行部署方式

### 3.1 ONNX Runtime 原生嵌入

- ONNX Runtime 官方 iOS 包提供 C/C++ 与 Objective-C API；Swift App 通过 bridging header 使用 `onnxruntime-objc`。[iOS Swift 示例](https://onnxruntime.ai/docs/tutorials/mobile/deploy-ios.html)、[Objective-C API](https://onnxruntime.ai/docs/api/objectivec/index.html)
- iOS 可用 CPU、XNNPACK、CoreML execution provider。官方建议量化模型先测 CPU；CoreML 的效果依模型和设备而定，若不支持的算子导致图被切成多个 partition，性能反而可能下降。[ORT mobile](https://onnxruntime.ai/docs/tutorials/mobile/)
- CoreML EP 支持 iOS 13+/macOS 10.15+，但动态 shape 可能影响性能，复杂模型的首次 CoreML 编译甚至可能耗时很久，应启用模型缓存并实测。[CoreML EP](https://onnxruntime.ai/docs/execution-providers/CoreML-ExecutionProvider.html)
- FlashNote 的最低版本是 iOS 17 / macOS 14，满足上述系统版本要求。

Direct ORT 并非“传一段 PCM 就有文字”。维护中的 SenseVoice ONNX 导出图接收：`x: Float32[N,T,560]`、`x_length: Int32[N]`、`language: Int32[N]`、`text_norm: Int32[N]`，输出 CTC logits；App 还要实现音频解码/重采样、fbank/LFR、CTC 去重去 blank、token 映射和 SentencePiece detokenize。[导出脚本](https://github.com/k2-fsa/sherpa-onnx/blob/master/scripts/sense-voice/export-onnx.py)

### 3.2 推荐：sherpa-onnx Swift/C API

SenseVoice 官方 README 把 sherpa-onnx 列为 iOS/Android/Swift 部署实践。它在 ONNX Runtime 外提供了 FlashNote 真正需要的完整边界：16 kHz 特征提取、模型 metadata、token 解码、语言/情感/事件字段、时间戳、VAD + offline recognizer 编排，并公开 Swift API 与 iOS arm64 支持。[SenseVoice 官方生态说明](https://github.com/QwenAudio/SenseVoice/blob/main/README.md#remarkable-third-party-work)、[sherpa-onnx SenseVoice](https://k2-fsa.github.io/sherpa/onnx/sense-voice/index.html)、[Swift binding](https://github.com/k2-fsa/sherpa-onnx/blob/master/swift-api-examples/SherpaOnnx.swift)

建议不要盲目打包社区仓库里的现成 `model.int8.onnx`；更稳妥的是固定官方 SenseVoiceSmall 权重 revision，用 sherpa-onnx 的可审计脚本自行导出 QUInt8 ONNX，记录 SHA-256、导出脚本版本和模型协议。这样既能复现，又能避免把第三方制品错误标注的许可证当成上游权重许可。

### 3.3 备选：官方 GGUF/C++ runtime

FunASR 已提供基于 llama.cpp/ggml 的 SenseVoice C++ runtime，支持 CPU、量化、FSMN-VAD、无 Python；它明确面向 laptop/phone/edge。[官方 GGUF runtime](https://github.com/modelscope/FunASR/blob/main/runtime/llama.cpp/sensevoice/README.md)

这条路线值得作为第二个 benchmark，但目前官方文档没有 Swift/XCFramework/iOS 示例，FlashNote 需要自己稳定 C ABI、打包 Apple slices、处理生命周期。首个 PoC 仍以 sherpa-onnx 为优先。

### 3.4 不推荐：本机 HTTP/Python

官方 FastAPI、FunASR/PyTorch 和 Docker 路径是桌面/服务器方案。[SenseVoice FastAPI](https://github.com/QwenAudio/SenseVoice/blob/main/README.md#deployment-with-fastapi) ONNX Runtime 官方 iOS 支持形态是直接链接 C/C++/Objective-C，而不是 Python。macOS 虽然能运行本机服务，但它会形成与 iOS 不同的进程、安装、端口、安全和生命周期体系，也无法兑现统一的原生离线引擎。因此它只适合开发对照，不进入 FlashNote 产品架构。

### 3.5 iOS 后台与资源约束

本地模型不会让长文件转写自动获得无限后台执行时间。Apple 对普通 `beginBackgroundTask` 只提供有限完成时间；`BGProcessingTask` 由系统决定何时启动。较新的 `BGContinuedProcessingTask` 可让用户主动开始的长任务从前台延续到后台，但系统仍可能因资源压力终止任务，且 FlashNote 的 iOS 17 最低版本意味着必须做 availability fallback。[Apple 后台策略](https://developer.apple.com/documentation/BackgroundTasks/choosing-background-strategies-for-your-app)、[长任务](https://developer.apple.com/documentation/BackgroundTasks/performing-long-running-tasks-on-ios-and-ipados)、[终止语义](https://developer.apple.com/documentation/backgroundtasks/bgcontinuedprocessingtask)

工程上应把文件转写做成可取消、可从最后完成的 VAD 段恢复的任务，并持久化进度；不能依赖 App 退到后台后一次跑完一小时录音。后台持续录音本身还需要 audio background mode；当前 `project.yml` / `Info.plist` 没有 `UIBackgroundModes=audio`，若产品要求锁屏录音 + 同时转写，需要另行评估电量、审核语义和中断恢复。

## 4. 已确认：音频输入要求

[官方模型配置](https://huggingface.co/FunAudioLLM/SenseVoiceSmall/blob/main/config.yaml)给出的前端是：

```text
16,000 Hz → 单声道 → Hamming 窗
25 ms frame / 10 ms shift → 80-bin log-mel filterbank
LFR m=7, n=6 → 每步 80 × 7 = 560 维 feature
→ prepend [language, event, emotion, ITN] 四个 query token
→ SAN-M encoder → CTC logits → greedy CTC + SentencePiece
```

[官方 GGUF runtime](https://github.com/modelscope/FunASR/blob/main/runtime/llama.cpp/sensevoice/README.md#architecture)明确要求 WAV 输入为 **16 kHz、mono、PCM16**。Python 示例所说“支持常见/任意音频格式”是 Python/ffmpeg/librosa 在图外解码和重采样，不代表 ONNX 图能直接读取 CAF/M4A/MP3。

Apple 侧可用 `AVAudioConverter` 做 PCM 位深、采样率、交错格式与声道转换；Apple 特别指出采样率转换要使用带 input block 的 `convert(to:error:withInputFrom:)`。[AVAudioConverter](https://developer.apple.com/documentation/avfaudio/avaudioconverter)、[TN3136](https://developer.apple.com/documentation/technotes/tn3136-avaudioconverter-performing-sample-rate-conversions)

## 5. 与 FlashNote 当前链路的精确衔接

### 5.1 手机/电脑麦克风录音

当前 [`AudioService.swift`](../../Services/Audio/AudioService.swift) 直接使用硬件 `inputFormat`，只有格式无效时才回落到 44.1 kHz；它写入 CAF，并把同一个 `AVAudioPCMBuffer` 推给实时引擎。硬件常见是 44.1/48 kHz，不能直接假设为 SenseVoice 的 16 kHz。

建议的数据流是：

```text
AVAudioEngine hardware buffer
  ├─ 原格式继续写 CAF（不改变现有录音资产）
  └─ AVAudioConverter → Float32 mono 16 kHz
       → 环形缓冲 / VAD
       → 每个语音段（上限 30 s）送 SenseVoice
       → VAD 段起点 + token timestamp → TranscriptSegment
```

`LiveTranscriptionEngine.append(_:)` 的现有抽象可以继续使用，但 SenseVoice 实现内部应立即重采样并串行进入专用 actor/queue，绝不能在 audio tap callback 上同步跑 fbank 或模型。VAD 结束后产生 `isFinal=true` 段；若 UI 需要中间字，可按较低频率对当前未结束段重复推理并标成 `isFinal=false`，端点时替换，不把 provisional text 持久化。

### 5.2 BLE 实时 Raw Opus

当前 [`OpusDecoder.swift`](../../Services/Audio/OpusDecoder.swift) 已确认设备格式：每个 40-byte Opus packet 解成 320 个 `Int16`、单声道 16 kHz，即 20 ms PCM。它已经精确满足 SenseVoice 的采样率/声道要求：

```text
CB08 BLE notify
  → 40-byte packet 重组
  → OpusDecoder → 320 × Int16 / 20 ms / 16 kHz mono
  → 转 Float32（按运行时约定归一化，或直接交给支持 sampleRate 的 wrapper）
  → 与麦克风共用同一 VAD / SenseVoice session
```

需要保留 packet 重组层：BLE notification 边界不应被当作模型 chunk 边界。一个 app 生命周期内复用同一个 `OpusDecoder` 和 recognizer session；暂停时 flush/close 当前 VAD 段，继续时新开段，以避免跨暂停拼接错误时间戳。

### 5.3 设备文件和导入文件

当前 [`DeviceTranscriptionService.swift`](../../Services/Device/DeviceTranscriptionService.swift) 下载阶段已经分片落盘，但 `.opus` 完成后又 `Data(contentsOf:)` 读入整个文件；`CB08OpusFileDecoder` 同时构造完整 `[Int16]` 与完整 WAV `Data`。这与一小时级录音的有界内存目标冲突。

SenseVoice 文件路径应改成：文件流式读取 40-byte packet → Opus 解码 → 16 kHz PCM 分块 → VAD/最多 30 秒窗口 → 逐段推理和落结果。对 CAF/M4A/MP3/WAV 则用 AVFoundation 流式解码并统一转 16 kHz mono，不一次性加载完整 waveform。固定窗口 fallback 使用官方建议的 30 秒 + 2 秒 overlap，并只对相邻窗口的精确重复做去重。

### 5.4 结果模型

FlashNote 的 `TranscriptSegment` 已有 `startTime/endTime/speaker/text/isFinal`，足够承接 VAD 段和时间戳；但目前没有 language/emotion/event 字段。首期可只保存 ASR text 和语言，情感/事件保留为引擎诊断数据；若要产品化展示，应新增明确的 segment metadata，而不要塞进正文或滥用 `speaker`。说话人字段保持 `nil`，直到另行接入并验证 CAM++。

## 6. 许可与分发

### 6.1 已确认事实

- SenseVoice 代码仓库是 [MIT](https://github.com/QwenAudio/SenseVoice/blob/main/LICENSE)。
- 官方权重不是 MIT/Apache；模型卡指向 [FunASR Model Open Source License Agreement v1.1](https://github.com/modelscope/FunASR/blob/main/MODEL_LICENSE)。该协议允许在遵守协议前提下使用、复制、修改、分享，要求注明出处/作者并保留模型名称。
- 协议同时包含“仅作为参考和学习使用”、禁止无端贬损等行为条款、自动接受未来修订、未填入具体国家/地区的适用法条款。它不是常规 OSI 开源许可证。
- SenseVoice README 及仓库成员回复称官方权重可商用，并建议在 About/Licenses 中注明 “SenseVoiceSmall by FunASR/FunAudioLLM”；但[最新澄清 issue #334](https://github.com/QwenAudio/SenseVoice/issues/334)已重新打开，状态说明明确称现有回复不是许可方最终确认，仍等待 license owner/core maintainer 确认。
- ONNX Runtime 是 [MIT](https://github.com/microsoft/onnxruntime/blob/main/LICENSE)，sherpa-onnx runtime 是 [Apache-2.0](https://github.com/k2-fsa/sherpa-onnx/blob/master/LICENSE)；两者本身可用于闭源/商业 App，遵守各自 notice 即可。运行时许可不能覆盖模型权重。

### 6.2 对 FlashNote 的实际含义

**闭源/收费 FlashNote：** 技术上可以集成，现有项目表述也倾向于允许商用；但在 App Store 发布或向用户分发 ONNX/GGUF 权重前，应取得阿里/FunASR 许可方书面确认，至少确认商业使用、量化/格式转换、随 App 或按需下载后的再分发、固定 revision 是否受未来协议修订影响。About/Licenses 页面应保留模型名、作者、来源链接、协议全文/链接及转换说明。

**开源 FlashNote：** 可以开源集成代码，但不能把自定义模型协议的权重声明为 FlashNote 的 MIT/Apache 内容。更稳妥的仓库结构是只提交下载/导出脚本、hash manifest 和 NOTICE，由用户从官方来源取得权重；release artifact 是否附带模型仍取决于上面的书面授权。

第三方 sherpa-onnx 模型包的 `LICENSE` 只有一个指向 FunASR 的链接，且历史页面/平台 metadata 曾出现 Apache-2.0 标记；这不足以把派生 ONNX 权重重新许可为 Apache-2.0。应始终追溯官方权重协议。

## 7. 建议 PoC 范围与决策门

### PoC 范围（建议 1–2 个迭代）

1. 固定官方权重 revision，自行导出 QUInt8 ONNX；记录导出器、ORT 版本和 SHA-256。
2. 原生接入 sherpa-onnx Swift/C API，先用 CPU EP、2 线程；不做 CoreML、不做 speaker diarization。
3. 打通三条相同输入边界：麦克风硬件格式 → 16 kHz mono；BLE 40-byte Opus → 16 kHz PCM16；本地文件 → 流式解码/重采样。
4. 文件转写使用 VAD 段，单段硬上限 30 秒；实时录音只承诺“停顿后快速定稿”。
5. 保存文本、语言、时间戳；情感/事件只做 debug 展示，等准确率评估后再决定产品化。
6. 在至少一台最低支持 iPhone、一台当前主流 iPhone 和 Apple Silicon Mac 上量冷启动、RTF、峰值内存、30 分钟温升与耗电。

### GO 条件

- 普通话/粤语的真实 FlashNote 录音集达到可接受准确率；
- 最低设备上 RTF、内存、温升达到产品门槛，录音 tap 无丢帧；
- 一小时文件不整段驻留内存，取消/后台/中断可恢复；
- 模型来源、转换与 hash 可复现；
- 商业使用和再分发得到书面确认，或产品改为用户自行下载且该用法也经审查。

### NO-GO 条件

- 产品需求必须是 Apple Speech 式低延迟、稳定逐字 partial，而不接受停顿后定稿；
- 必须在很老的低内存设备上常驻模型，实测出现频繁内存终止或严重热降频；
- 必须随商业 App 分发权重，但无法消除当前模型许可歧义；
- 需要 checkpoint 原生提供可靠说话人分离。

## 8. 最终建议

**做 PoC，但把承诺收窄。** SenseVoiceSmall 很适合 FlashNote 的中文/粤语离线文件转写，也能以 VAD 端点方式提供可用的录音中反馈；FlashNote 现有 BLE Opus 恰好已经是 16 kHz 单声道，适配成本低。真正的不确定性不在“能不能在 Apple 设备跑”，而在三件事：iPhone 实测 footprint/热表现、准实时 UX 是否满足用户预期、权重商业再分发许可是否足够明确。

首选路线是 **sherpa-onnx 原生 wrapper + 自行导出的官方 INT8 权重 + CPU EP**。Direct ONNX Runtime 可作为后续减依赖/定制优化路线；CoreML EP、GGUF 和说话人分离均应在首个 PoC 之后分别验证。
