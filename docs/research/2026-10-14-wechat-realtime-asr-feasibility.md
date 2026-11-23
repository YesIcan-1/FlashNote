# FlashNote 接入微信输入法式实时语音识别的可行性（2026-10-14）

## 结论

**不建议、也没有已确认的受支持方式，把微信输入法（WeType）的实时语音识别直接嵌入 FlashNote。** 截至核验日，微信输入法官方只把它作为输入法自身功能发布；现行微信 Open SDK 明列的能力是分享与收藏、微信登录、微信支付，没有 WeType ASR、实时音频流或转写接口。公开资料未发现 WeType 面向第三方原生 App 的 Swift/Objective-C SDK、HTTP 或 WebSocket API。

可行路线按优先级是：

1. **主路线：百炼 `qwen3-asr-flash-realtime` 的官方 WebSocket API**，接在 FlashNote 已有 `AVAudioPCMBuffer` 流式引擎边界之后；生产版由后端签发临时 API Key。
2. **Apple 平台兜底：Apple Speech**。项目已有 `SFSpeechAudioBufferRecognitionRequest` 实现，可继续作为低配置/离线优先通道。
3. **腾讯系备选：腾讯云实时语音识别**。这是公开的第三方 PaaS/SDK，但官方没有说明它与 WeType 使用同一模型或达到相同效果。
4. **macOS 实验兼容：SayAll 式“虚拟麦克风 + 快捷键 + 输入法”桥接**。能借用 WeType 的产品体验，但不是 ASR API；只适合作为用户主动开启的兼容模式，不适合成为 FlashNote 的核心转写后端，也不能自然覆盖 iOS。

## 1. 微信输入法 / WeType：产品能力存在，嵌入接口未公开

### 已确认事实

- [微信输入法官网](https://z.weixin.qq.com/)的更新记录显示，Mac 版已支持长按快捷键启动语音、实时写入当前输入框、连续语音输入，并在后续版本加入自定义快捷键、选择麦克风和切换窗口/输入框后不中断等能力；这能确认用户看到的体验是真实产品功能。
- [微信输入法 macOS 官方更新日志](https://z.weixin.qq.com/web/changelog/macos)和[官网 sitemap](https://z.weixin.qq.com/sitemap.xml)是产品下载与版本信息入口，未提供开发者 SDK/API 文档入口。
- 现行[微信 Open SDK for iOS 资源页](https://developers.weixin.qq.com/doc/oplatform/Mobile_App/Downloads/iOS_Resource.html)明确介绍其能力为“分享与收藏、微信登录和微信支付”；[iOS 接入指南](https://developers.weixin.qq.com/doc/oplatform/Mobile_App/Access_Guide/iOS.html)也按这些能力说明接入，没有语音识别或 WeType 接口。
- 一个名为 [`WXVoice_iOS_3.0.2.zip`](https://res.wx.qq.com/open/zh_CN/htmledition/res/dev/download/sdk/WXVoice_iOS_3.0.2.zip) 的旧官方静态包目前仍可下载。包内文件时间为 2017–2018 年，头文件包含流式中间结果、连续识别和调用方追加 8/16 kHz、16-bit 单声道 PCM 的接口。它名为微信语音 SDK，不是微信输入法/WeType SDK，也不在现行 Open SDK 能力清单中。

### 推断

- **当前公开、受支持的答案是“没有 WeType ASR 接口可供 FlashNote 直接集成”。** 这是由官网、现行 Open SDK 能力目录及公开文档的交叉核验得出的结论，不应扩展成“腾讯内部绝对不存在接口”。
- 旧 `WXVoice_iOS` 下载文件本身不能证明其服务端仍开放、第三方 AppID 仍可开通、配额仍可申请、许可仍适合新产品，或可兼容当前 iOS/Xcode；没有腾讯书面确认前，不应把它列入产品技术选型。
- 不应通过抓包、逆向 WeType 私有协议或模拟其内部请求来获得“同款模型”。这没有公开兼容保证，也缺少可核验的授权边界。

### 未知

- WeType 内部模型名称、云端/端侧切换方式、服务协议和 SLA 均未公开。
- 腾讯是否向特定商务伙伴提供私有接口未知；若希望探索，只能向腾讯寻求书面合作与现行技术/授权材料。

## 2. 微信小程序语音能力不适用于独立原生 App

### 已确认事实

- [`RecorderManager`](https://developers.weixin.qq.com/miniprogram/dev/api/media/recorder/RecorderManager.html) 是微信小程序的全局录音管理器；它可通过 `onFrameRecorded` 回调音频帧，但本身不是 ASR。
- 腾讯官方示例 [`Tencent/Face2FaceTranslator`](https://github.com/Tencent/Face2FaceTranslator) 使用“微信同声传译”插件提供流式语音识别。接入要求包括小程序 AppID、在小程序后台添加插件、在 `app.json` 声明插件，并在小程序 JavaScript 中使用插件接口；微信的[插件使用文档](https://developers.weixin.qq.com/miniprogram/dev/framework/plugin/using.html)明确通过 `app.json`、`plugin://` 和 `requirePlugin` 运行。
- 官方[微信同声传译能力页](https://developers.weixin.qq.com/miniprogram/dev/platform-capabilities/extended/translator.html)与上述示例描述的是微信小程序运行时能力。

### 结论

独立 SwiftUI iOS/macOS App 不能直接调用 `wx.getRecorderManager`、`requirePlugin` 或小程序插件。把 FlashNote 另做成小程序会是不同产品形态，并不能把插件“链接”进现有原生 App。官方示例较旧，当前插件准入、配额和 SLA 仍需在小程序后台实测。

## 3. 可合法集成的实时 ASR 路线

### 3.1 百炼 Qwen3-ASR（推荐主路线）

#### 已确认事实

- 百炼当前公开模型 ID 是 **`qwen3-asr-flash-realtime`**，不是项目设置中的 `qwen3-asr-realtime`。官方[语音识别模型总览](https://help.aliyun.com/zh/model-studio/asr-model/)将其列为 WebSocket 实时模型，支持 PCM/Opus、8 kHz 或 16 kHz、单声道，音频时长不限，并覆盖普通话、四川话、闽南语、吴语、粤语及多种外语。
- 官方[实时语音识别指南](https://help.aliyun.com/zh/model-studio/real-time-speech-recognition-user-guide)给出完整原始 WebSocket 流程：持续发送 `input_audio_buffer.append`，接收增量文本和 `conversation.item.input_audio_transcription.completed` 最终结果；可使用服务端 VAD 或客户端 `commit`。
- `qwen3-asr-flash-realtime` **当前不返回时间戳**；同一官方指南建议需要句/字时间戳时选择 Qwen-Audio-ASR-Streaming、Fun-ASR-Realtime 或 Paraformer。
- 百炼官方要求不要把长期 API Key 硬编码进客户端，并提供[临时 API Key](https://help.aliyun.com/zh/model-studio/application-obtain-temporary-authentication-token)：由安全后端生成，默认 60 秒、最长 1800 秒，适用于浏览器和移动 App 等不可信环境。

#### 与 FlashNote 的集成边界（基于现有仓库的推断）

```text
麦克风 AVAudioPCMBuffer ─┐
                         ├→ 格式归一化（单声道 PCM16 / 16 kHz）
BLE Opus → 解码/重采样 ──┘        ↓
                         QwenRealtimeEngine（WebSocket）
                           ├→ 增量文本 → onPartialText
                           └→ 最终文本 → onSegment
```

- 现有 `LiveTranscriptionEngine.append(AVAudioPCMBuffer)` 已是合适的适配边界；麦克风采集、BLE 解码、录音落盘不应耦合到百炼客户端。
- 先把 `AppSettings.qwenASRRealtimeModel` 默认值改为官方模型 ID，并由服务端配置覆盖，避免把模型名永久写死。（本报告不修改源码。）
- 若继续使用 Qwen3-ASR，`TranscriptSegment` 的时间只能由客户端按音频游标/VAD 边界近似生成；若准确时间戳是硬需求，应改选官方明确返回时间戳的流式模型。
- 面向普通用户发行时，FlashNote 后端保存长期 Key、签发临时 Key；客户端只持短期凭证。仅限个人 BYOK 的原型可以让用户自行填写 Key，但仍需明确泄露与计费风险。
- 上线前必须用真实麦克风和 BLE 16 kHz Opus 两条链路做延迟、断句、网络恢复、长会话、中文方言和后台/前台切换实测；“可调用”不等于已达到 WeType 的主观体验。

### 3.2 Apple Speech（现有兜底）

- Apple [Speech framework](https://developer.apple.com/documentation/speech/)支持实时或录音文件转写，并明确可在没有键盘的情况下实现类似听写体验。
- [`SFSpeechAudioBufferRecognitionRequest`](https://developer.apple.com/documentation/speech/sfspeechaudiobufferrecognitionrequest)可持续追加 PCM buffer；[`SFSpeechRecognitionRequest`](https://developer.apple.com/documentation/speech/sfspeechrecognitionrequest)支持中间结果和要求端侧识别。
- FlashNote 已有 `SpeechEngine` 使用上述机制，因此它适合作为无百炼配置、弱网或隐私优先时的兜底；实际端侧支持仍需按设备和语言检查，不能假定所有语言都离线可用。

### 3.3 腾讯云 ASR（需要腾讯公开能力时）

- 腾讯云公开提供[实时语音识别 V2 iOS SDK](https://cloud.tencent.com/document/product/1093/133355)，通过 WebSocket 返回实时结果；[SDK 概览](https://cloud.tencent.com/document/product/1093/52554)也把 iOS 实时识别列为正式客户端能力。
- 这是可签约、可计费、可获得正式文档的腾讯云服务，适合作为“腾讯系 ASR”候选；但**没有官方依据证明它等同于 WeType 的模型、后处理或交互体验**。macOS 支持范围和原始 WebSocket 接法应在采购/技术评审时向腾讯云确认。

## 4. SayAll 式桌面桥接：可实验，不宜做核心后端

### 已确认事实

- SayAll 官方仓库说明的链路是：把设备音频写入 `MiRemoteV 2ch` 或其他回环音频设备，在目标语音输入 App 中选同一设备作为麦克风，再通过 Fn/修饰键触发输入。它明确兼容微信等语音入口，但 SayAll 自身不提供 ASR：[使用语音输入与权限说明](https://github.com/HD838A/remote-mic-app#使用语音输入)。
- 该流程需要安装兼容虚拟麦克风驱动；按键映射涉及蓝牙、输入监控与辅助功能权限。微信输入法和虚拟设备必须保持正确选择，前台还要有可接收文字的输入框。
- Apple 的 iOS [Custom Keyboard](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/CustomKeyboard.html)文档明确指出自定义键盘扩展不能访问设备麦克风。因此不能把 macOS 的虚拟麦克风/全局快捷键方案直接平移为 FlashNote 的 iOS 键盘集成。

### 对 FlashNote 的适用性推断

- **适合**：macOS 高级用户已有 WeType，希望在任意当前输入框使用 FlashNote/录音器音频；可提供独立的“系统语音输入桥接”实验开关。
- **不适合**：FlashNote 自己的结构化实时转写。输入法只把文字写进焦点文本框，FlashNote 拿不到受支持的会话状态、稳定的增量/最终事件、时间戳、置信度、错误码或重试语义。
- 体验成本包括驱动安装与升级、设备选择、快捷键冲突、焦点漂移、辅助功能/输入监控授权，以及 WeType 更新后行为变化。音频还进入另一个进程/服务，隐私告知与用户同意要单独处理。
- iOS 没有与该 macOS HAL 虚拟设备 + 全局按键注入等价的产品路径；因此它不能成为双平台统一架构。
- 若借鉴 SayAll 的架构，应自行实现清晰的互操作层；直接复用其 GPL-3.0 代码前需单独评估开源许可证义务。

## 决策建议

1. 把“微信同款”定义为可测的体验指标（首字延迟、稳定增量、断句、标点、方言、噪声、长会话恢复），不要定义为调用 WeType 私有模型。
2. 以 `qwen3-asr-flash-realtime` 做第一条正式云端适配器，保留 Apple Speech 兜底；若要求准确时间戳，先比较 Qwen-Audio-ASR-Streaming / Fun-ASR-Realtime。
3. 在正式发行架构中加入短期凭证服务，不把百炼长期 Key 随 App 分发。
4. 腾讯云 ASR 可进入同一真实音频 A/B 测试，但不能宣传为“微信输入法同款”。
5. SayAll 式桥接只做 macOS 可选实验功能；不把其可用性计入 FlashNote 核心转写 SLA。

## 证据强度与未知项

- **高置信事实**：现行微信 Open SDK 能力范围、小程序插件运行边界、百炼/Apple/腾讯云公开 API 能力、SayAll 的公开工作方式。
- **基于公开资料的结论**：未发现 WeType 第三方 ASR API；这是“没有公开受支持入口”，不是对腾讯内部系统的绝对否定。
- **仍需实测**：Qwen/Apple/腾讯云在 FlashNote 两类音频源上的准确率与端到端延迟；Qwen3 无原生时间戳时的时间轴策略；macOS WeType 桥接在当前版本上的稳定性。
- **仍需外部确认**：旧 `WXVoice_iOS` 的现行授权、开通、配额、服务状态与兼容性；任何腾讯商务合作接口。
