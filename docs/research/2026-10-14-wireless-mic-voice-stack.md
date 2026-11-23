# “无线麦”语音方案核验（2026-10-14）

## 结论

按产品名精确匹配，用户所说的开源 App 应是 **无线麦 SayAll**：

- macOS 主仓库：[HD838A/remote-mic-app](https://github.com/HD838A/remote-mic-app)
- Windows 仓库：[GetSayAll/remote-mic-app-windows](https://github.com/GetSayAll/remote-mic-app-windows)

它与此前参考的 [uui77/NextProto](https://github.com/uui77/NextProto) 是两个不同项目。

**一句话答案：SayAll 本身不做语音识别，也没有可指认的“语音模型/音色”；它做的是蓝牙收音、解码、虚拟麦克风转发和快捷键触发。微信输入法只是可选的外部 ASR 工具之一，不是 SayAll 在代码里调用的微信语音 API。**

如果用户选择微信输入法，音频最终由微信输入法读取并识别；其内部采用哪一个精确 ASR 模型，SayAll 源码没有披露，微信输入法公开资料也没有给出足以核验的具体模型名。

## SayAll 的实际语音链路

```text
小米蓝牙语音遥控器
  → BLE ATVV 音频特征
  → IMA ADPCM 解码
  → 16 kHz / 单声道 PCM
  → 虚拟音频设备（macOS: MiRemoteV 2ch / BlackHole；Windows: VB-CABLE 等）
  → 合成 Fn、Ctrl+Win 等按键
  → 用户选定的第三方语音工具完成 ASR 并把文字写入输入框
```

### macOS 证据

核验基准为提交 [`a27f817`](https://github.com/HD838A/remote-mic-app/tree/a27f8177954369ee7c581744557a97fcfee6051e)。

1. README 要求 SayAll 与目标听写工具选择同一个回环设备，并明确兼容豆包、微信、Typeless，而不是绑定单一服务：
   - [`README.md`：选择 `MiRemoteV 2ch` / 回环设备](https://github.com/HD838A/remote-mic-app/blob/a27f8177954369ee7c581744557a97fcfee6051e/README.md#L146-L160)
   - [`README.md`：Fn 用于兼容豆包、微信、Typeless](https://github.com/HD838A/remote-mic-app/blob/a27f8177954369ee7c581744557a97fcfee6051e/README.md#L154-L166)
   - [`README.md`：回环驱动由 BlackHole 派生](https://github.com/HD838A/remote-mic-app/blob/a27f8177954369ee7c581744557a97fcfee6051e/README.md#L266-L272)
2. 音频不是送进 ASR SDK：
   - [`ATVVProtocol.swift`：16 kHz、IMA ADPCM 解码及 PCM 后处理](https://github.com/HD838A/remote-mic-app/blob/a27f8177954369ee7c581744557a97fcfee6051e/Sources/RemoteMic/ATVVProtocol.swift#L3-L16)
   - [`ATVVProtocol.swift`：`IMAADPCMDecoder`](https://github.com/HD838A/remote-mic-app/blob/a27f8177954369ee7c581744557a97fcfee6051e/Sources/RemoteMic/ATVVProtocol.swift#L98-L172)
   - [`XiaomiBluetoothBridge.swift`：BLE 帧解码后回调 PCM 样本](https://github.com/HD838A/remote-mic-app/blob/a27f8177954369ee7c581744557a97fcfee6051e/Sources/RemoteMic/XiaomiBluetoothBridge.swift#L1032-L1075)
   - [`BridgeAppModel.swift`：PCM 送入 `audioOutput.enqueue`](https://github.com/HD838A/remote-mic-app/blob/a27f8177954369ee7c581744557a97fcfee6051e/Sources/RemoteMic/BridgeAppModel.swift#L5992-L6030)
   - [`AudioOutput.swift`：`AVAudioEngine` 使用 16 kHz 单声道格式并写入选定设备](https://github.com/HD838A/remote-mic-app/blob/a27f8177954369ee7c581744557a97fcfee6051e/Sources/RemoteMic/AudioOutput.swift#L846-L851)
3. “唤起语音”是系统按键事件，不是微信接口：
   - [`KeyboardInjector.swift`：合成语音键按下/释放](https://github.com/HD838A/remote-mic-app/blob/a27f8177954369ee7c581744557a97fcfee6051e/Sources/RemoteMic/KeyboardInjector.swift#L225-L249)
   - [`OnboardingFlow.swift`：可选工具包括豆包、微信、Typeless、Vokie、其他](https://github.com/HD838A/remote-mic-app/blob/a27f8177954369ee7c581744557a97fcfee6051e/Sources/RemoteMic/OnboardingFlow.swift#L124-L169)
   - 微信输入法只以输入源 ID `com.tencent.inputmethod.wetype.pinyin` 出现，用于选择/检测输入源，不是云 API 客户端。
4. 公共 Swift 包依赖只有 Sparkle 等本地模块，没有 Speech、Whisper、FunASR、腾讯或微信 ASR SDK：[`Package.swift`](https://github.com/HD838A/remote-mic-app/blob/a27f8177954369ee7c581744557a97fcfee6051e/Package.swift#L1-L20)。
5. “回眸”里的文字也不是 SayAll 自己识别出来的：它通过 macOS Accessibility 观察前台输入框的文本变化：[`TranscriptCaptureCoordinator.swift`](https://github.com/HD838A/remote-mic-app/blob/a27f8177954369ee7c581744557a97fcfee6051e/Sources/RemoteMic/TranscriptCaptureCoordinator.swift#L44-L96)。

### Windows 证据

核验基准为提交 [`2d860ed`](https://github.com/GetSayAll/remote-mic-app-windows/tree/2d860ed6c76784de175487f3c0f9a9de324acacb)。

- 当前专用仓库 README 已写明支持豆包输入法、微信输入法、Vokie 和其他工具，并非只支持微信：[`README.md`](https://github.com/GetSayAll/remote-mic-app-windows/blob/2d860ed6c76784de175487f3c0f9a9de324acacb/README.md#L40-L55)。macOS 主仓 README 中“第一个预览版仅支持微信输入法”的文字是旧版状态，不能代表当前 Windows 实现。
- Windows 端同样把 16 kHz、单声道、S16 PCM 通过 WASAPI 写入渲染端点/虚拟声卡：[`audio.rs`](https://github.com/GetSayAll/remote-mic-app-windows/blob/2d860ed6c76784de175487f3c0f9a9de324acacb/crates/sayall-windows/src/audio.rs#L255-L270)、[`write_to_device`](https://github.com/GetSayAll/remote-mic-app-windows/blob/2d860ed6c76784de175487f3c0f9a9de324acacb/crates/sayall-windows/src/audio.rs#L1148-L1175)。
- 微信路径只是用公开 Windows TSF API 激活 WeType 输入法，再发送其默认 `Ctrl+Win` 热键；同一映射还支持豆包，Vokie/其他工具则不切输入法：[`ime.rs`](https://github.com/GetSayAll/remote-mic-app-windows/blob/2d860ed6c76784de175487f3c0f9a9de324acacb/crates/sayall-windows/src/ime.rs#L1-L36)、[`ime_target_for`](https://github.com/GetSayAll/remote-mic-app-windows/blob/2d860ed6c76784de175487f3c0f9a9de324acacb/crates/sayall-windows/src/ime.rs#L53-L95)。

## 是否“调用微信语音”

需要区分两层：

- **SayAll → 微信服务端 API：没有找到。** 公开语音主链路没有微信 SDK、微信云、微信 ASR HTTP/WebSocket 端点或 API Key；它只操作系统音频设备、输入源和快捷键。
- **用户选择微信输入法后 → 微信输入法执行识别：是。** 此时微信输入法作为另一个本机进程，从虚拟麦克风取音并完成语音转文字。网络/离线处理方式和具体模型由微信输入法自身决定，不属于 SayAll 的调用栈。

因此，准确说法不是“无线麦调用了微信语音接口”，而是“无线麦可以把微信输入法当作外部语音识别前端来驱动”。

## 与 NextProto 的消歧

如果问题实际指的是此前讨论的 **NextProto（QS668/CB08 录音卡）**，答案完全不同：

- 桌面版内置本地 ASR：`funasr-onnx`，默认 **SenseVoiceSmall**，也支持 **Paraformer**，外加 FSMN-VAD；模型下载后离线运行。证据：[`desktop/recorder/asr.py`](https://github.com/uui77/NextProto/blob/81167c71239083069b372f8691f57248404b2a46/desktop/recorder/asr.py#L1-L5)、[模型定义](https://github.com/uui77/NextProto/blob/81167c71239083069b372f8691f57248404b2a46/desktop/recorder/asr.py#L50-L69)、[模型构造](https://github.com/uui77/NextProto/blob/81167c71239083069b372f8691f57248404b2a46/desktop/recorder/asr.py#L303-L359)。
- 微信小程序版使用微信的 `wx.request` 作为网络能力，但 ASR 服务商是 **阿里云百炼 DashScope**，默认模型 `paraformer-1`，请求直接发往 `dashscope.aliyuncs.com`：[`transcribe.js`](https://github.com/uui77/NextProto/blob/81167c71239083069b372f8691f57248404b2a46/miniprogram/pages/transcribe/transcribe.js#L170-L233)。
- 所以 NextProto 小程序“运行在微信里”，但**没有调用微信语音识别**；它调用的是阿里云 ASR。

## 已知边界与不确定项

- 本结论核验的是公开仓库在上述提交的源码。macOS `Package.swift` 支持按本地路径注入可选的私有 `SayAllAI` 包，iOS App 也在私有仓库；这些闭源部分无法完全审计。不过公开集成层只向该私有模块传递语音会话开始/结束，不传递 PCM 样本：[`PrivateFeatureIntegration.swift`](https://github.com/HD838A/remote-mic-app/blob/a27f8177954369ee7c581744557a97fcfee6051e/Sources/RemoteMic/PrivateFeatureIntegration.swift#L102-L111)。核心语音输入功能不依赖它。
- SayAll README [声明不会上传或保存语音](https://github.com/HD838A/remote-mic-app/blob/a27f8177954369ee7c581744557a97fcfee6051e/README.md#L213-L219)，但这是项目方声明；本次没有对已签名发行包做动态抓包。
- 微信输入法内部的精确 ASR 模型、云端/离线切换策略没有可核验的一手源码，因此不应猜测成“腾讯混元”“微信同款模型”或其他具体方案。
- 微信公众号文章仅用于提供线索，没有作为技术结论的证据。
