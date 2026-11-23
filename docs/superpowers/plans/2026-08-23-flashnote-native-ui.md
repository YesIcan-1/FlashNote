# FlashNote 原生 UI 实施计划

> **执行状态：** 用户已确认已展示的界面，按本计划直接实施。

**目标：** 用 SwiftUI 还原已确认的 FlashNote 工作台、详情、文件、录音笔和设置界面，同时将每个视觉入口连接到真实本地资料库与设备状态。

**架构：** 保留 `AppEnvironment` 的单一 `DeviceViewModel` 会话和 `RecordingStore` 的资料边界。新增设计系统组件与少量轻量视图模型/路由状态；视图不得持有 BLE 协议细节。设备与云服务进度通过可观察状态驱动。

**技术栈：** SwiftUI、Observation、CoreBluetooth、FlashNoteCore、Swift Testing。

---

### 任务 1：建立原生视觉基础

**文件：** `DesignSystem/AppTheme.swift`、`DesignSystem/Components.swift`、必要的组件测试

- [ ] 将背景、内容面、次级面、边框、强调、成功、警告、危险和阴影改为语义颜色。
- [ ] 新增通用的页面标题、状态胶囊、分区标题、信息卡、空状态和等宽元数据组件。
- [ ] 让所有组件在 `colorScheme` 下保持可读对比，不为单个页面硬编码白/黑。

### 任务 2：统一导航、路由与数据入口

**文件：** `App/RootView.swift`、`App/AppEnvironment.swift`、`Features/Recordings/RecordingListView.swift`

- [ ] 统一 macOS 侧栏与 iOS 标签页的五个目的地，并移除重复的设置弹窗入口。
- [ ] 建立按录音 ID 打开详情的稳定路由，使工作台、文件和录音列表行为一致。
- [ ] 保证只有设备页/设备文件页启动会话；其它导航不碰蓝牙权限。

### 任务 3：重建工作台与录音详情

**文件：** `Features/Workbench/WorkbenchView.swift`、`Features/Detail/RecordingDetailView.swift`、播放/转写支持文件

- [ ] 实现日期上下文、已连接设备状态、继续处理卡、真实 AI 摘要条和可点击最近录音。
- [ ] 将详情改为宽屏双列、窄屏堆叠；音频、全文、纪要均绑定真实的录音记录。
- [ ] 添加重试全文转写、重试 AI 纪要和本地删除确认；无音频/无 API 时显示原因与下一步。

### 任务 4：重建文件与设备界面

**文件：** `Features/Files/FileCenterView.swift`、`Features/Device/DevicePanelView.swift`、`Features/Device/DeviceViewModel.swift`

- [ ] 实现本地/设备分段、搜索、文件行、状态、刷新、下载进度和详情路由。
- [ ] 实现设备健康概览、实时会话、控制区、设备文件表和高级区域。
- [ ] 修正 QS668 录音状态映射，暴露最新的电量、固件、文件数与下载错误。
- [ ] 不在任何非设备页面常驻录音笔 UI。

### 任务 5：重建设置并完善数据清理

**文件：** `Features/Settings/SettingsView.swift`、`App/AppSettings.swift`、`FlashNoteCore/.../RecordingStore.swift`、`FlashNoteCore/.../FileRecordingStore.swift`

- [ ] 将表单替换为已确认的设置分区，同时保留已有外观、模型检测、Qwen、DeepSeek、可选本地模型和上传服务字段。
- [ ] 添加 API 配置的验证/模型读取反馈，不重复模型选择器。
- [ ] 为本地录音删除添加录音 JSON、全文、全部纪要和音频文件的级联清理。

### 任务 6：设备与转写可靠性续作

**文件：** `Services/Device/*`、`Services/Transcription/*`、对应测试

- [ ] 把下载的中断、续传、候选文件与本地落地状态连接到新 UI，不伪报成功。
- [ ] 将设备实时音频会话桥接为可恢复的录音记录和实时全文状态；外部 Qwen 服务未配置时保留可下载音频。
- [ ] 接入被授权的 Qwen 上传签名服务后实现长音频上传/轮询；在此之前保留明确的配置状态，而不嵌入长效密钥。

### 任务 7：验证与交付

- [ ] 为状态映射、大小格式化、级联删除和路由增加/更新测试。
- [ ] 运行 macOS 测试、macOS 构建和未签名 iOS 真机构建。
- [ ] 人工检查五页、亮/暗主题、最近内容跳转、设备文件切换和无蓝牙启动路径。
- [ ] 对真实 CB08 做连接/下载/断线续传/删除/实时流回归，并将仅依赖硬件或云凭据的结果单列报告。
