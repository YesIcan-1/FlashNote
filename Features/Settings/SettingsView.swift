import SwiftUI
import FlashNoteCore
#if os(macOS)
import AppKit
import UserNotifications
#endif

/// 设置页以产品分区组织，避免系统 Form 将模型和设备操作混在一处。
struct SettingsView: View {
    @Environment(\.appEnvironment) private var environment
    @State private var settings: AppSettings?
    @State private var availableModels: [AIProvider: [String]] = [:]
    @State private var modelLoadError: String?
    @State private var isLoadingModels = false
    @State private var didClearRememberedDevice = false
    #if os(macOS)
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    #endif
    @AppStorage("liveTranscriptionLocale") private var liveTranscriptionLocale = "zh-CN"

    var body: some View {
        Group {
            if let settings { content(settings) }
            else { ProgressView("正在读取设置…") }
        }
        .navigationTitle("设置")
        .onAppear { if settings == nil { settings = AppSettings(storeDirectory: AppEnvironment.defaultStoreDirectory()) } }
        #if os(macOS)
        .task { notificationStatus = await AppNotificationService.shared.authorizationStatus() }
        #endif
    }

    private func content(_ settings: AppSettings) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                liveTranscriptionGroup
                transcriptionGroup(settings)
                minutesGroup(settings)
                qwenGroup(settings)
                #if os(macOS)
                notificationGroup
                #endif
                deviceGroup
            }
            .padding(.horizontal, 28).padding(.vertical, 24)
            .frame(maxWidth: 820, alignment: .leading)
        }
        .background(AppTheme.pageBackground)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("设置").font(.system(size: 30, weight: .bold, design: .rounded))
            Text("管理实时识别、文件转写、AI 内容与录音笔。")
                .font(.subheadline).foregroundStyle(AppTheme.secondaryText)
        }
    }

    private var liveTranscriptionGroup: some View {
        SettingsGroup(title: "实时转写", subtitle: "录音时一边收音一边显示识别文字", icon: "waveform.badge.mic") {
            Picker("识别语言", selection: $liveTranscriptionLocale) {
                Text("中文").tag("zh-CN")
                Text("English").tag("en-US")
            }
            .pickerStyle(.segmented).frame(maxWidth: 320)
            SettingHint("使用系统语音识别；切换语言会在下一次开始录音时生效。停止录音时会保存已识别但尚未定稿的文字。")
        }
    }

    private func transcriptionGroup(_ settings: AppSettings) -> some View {
        SettingsGroup(title: "全文转写", subtitle: "导入音频和下载设备文件使用此默认引擎", icon: "waveform") {
            Picker("默认转写引擎", selection: Binding(get: { settings.transcriptionEngine }, set: { settings.transcriptionEngine = $0 })) {
                ForEach(TranscriptionEngineChoice.allCases) { choice in Text(choice.displayName).tag(choice) }
            }
            .pickerStyle(.segmented).frame(maxWidth: 440)
            if settings.transcriptionEngine == .whisperKit {
                SettingHint(WhisperKitEngine.localConfiguration(at: WhisperKitEngine.defaultLocalModelRoot) == nil
                    ? "首次转写需下载约 626 MB 的多语言模型；下载完成后，音频在本机离线转写。"
                    : "本地多语言模型已就绪，音频在本机离线转写。")
            } else {
                SettingHint("云端 Whisper 使用当前 AI 服务的 API 地址和密钥；服务须支持 whisper-1 音频转写接口。")
            }
        }
    }

    private func minutesGroup(_ settings: AppSettings) -> some View {
        SettingsGroup(title: "AI 内容生成", subtitle: "转写完成后生成会议纪要和洞察", icon: AppIcons.sparkle) {
            Picker("服务商", selection: Binding(get: { settings.aiProvider }, set: { settings.aiProvider = $0; modelLoadError = nil })) {
                ForEach(AIProvider.allCases) { provider in Text(provider.displayName).tag(provider) }
            }
            .pickerStyle(.segmented).frame(maxWidth: 520)
            SettingsTextField("API 地址", text: Binding(get: { settings.llmBaseURL }, set: { settings.llmBaseURL = $0 }), placeholder: settings.aiProvider.defaultBaseURL)
            if let models = availableModels[settings.aiProvider], !models.isEmpty {
                if !models.contains(settings.llmModel) {
                    SettingsTextField("模型", text: Binding(get: { settings.llmModel }, set: { settings.llmModel = $0 }), placeholder: settings.aiProvider.defaultModel)
                }
                Picker("可用模型", selection: Binding(get: { settings.llmModel }, set: { settings.llmModel = $0 })) {
                    ForEach(models, id: \.self) { Text($0).tag($0) }
                }
                .frame(maxWidth: 520, alignment: .leading)
            } else {
                SettingsTextField("模型", text: Binding(get: { settings.llmModel }, set: { settings.llmModel = $0 }), placeholder: settings.aiProvider.defaultModel)
            }
            SecureField("\(settings.aiProvider.displayName) API Key", text: Binding(get: { settings.llmAPIKey }, set: { settings.llmAPIKey = $0 }))
                .textFieldStyle(.roundedBorder).frame(maxWidth: 520)
            HStack(spacing: 10) {
                Button(isLoadingModels ? "正在识别模型…" : "识别可用模型") { loadModels(settings) }
                    .buttonStyle(.bordered).disabled(isLoadingModels || settings.llmAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if let modelLoadError { Text(modelLoadError).font(.caption).foregroundStyle(AppTheme.destructive) }
            }
            SettingHint("DeepSeek 与千问各自保存地址、模型和密钥；切换服务商后立即生效。")
        }
    }

    private func qwenGroup(_ settings: AppSettings) -> some View {
        SettingsGroup(title: "高级云端配置", subtitle: "千问语音识别参数", icon: "cloud") {
            SettingHint("DashScope API Key 与上方千问服务商共用。以下参数已保存，Qwen3-ASR 接入后生效。")
            SettingsTextField("Workspace ID", text: Binding(get: { settings.qwenASRWorkspaceID }, set: { settings.qwenASRWorkspaceID = $0 }), placeholder: "长文件转写需要")
            SettingsTextField("文件模型", text: Binding(get: { settings.qwenASRFileModel }, set: { settings.qwenASRFileModel = $0 }), placeholder: "qwen3-asr-flash-filetrans")
            SettingsTextField("实时模型", text: Binding(get: { settings.qwenASRRealtimeModel }, set: { settings.qwenASRRealtimeModel = $0 }), placeholder: "qwen3-asr-realtime")
        }
    }

    private var deviceGroup: some View {
        SettingsGroup(title: "录音笔", subtitle: "已连接设备会被记住，并仅在设备相关页面尝试恢复", icon: AppIcons.device) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(didClearRememberedDevice ? "已清除已记住设备" : "管理已记住设备")
                    Text("清除后不会自动尝试恢复，仍可在录音笔页重新扫描。")
                        .font(.caption).foregroundStyle(AppTheme.secondaryText)
                }
                Spacer()
                Button("清除记住的设备", role: .destructive) {
                    CB08Central.shared.clearRememberedDevice()
                    didClearRememberedDevice = true
                }.buttonStyle(.bordered)
            }
        }
    }

    #if os(macOS)
    private var notificationGroup: some View {
        SettingsGroup(title: "系统通知", subtitle: "下载、转写和会议纪要任务的开始与结果", icon: "bell") {
            HStack {
                Text(notificationStatus == .authorized || notificationStatus == .provisional
                     ? "已允许通知" : notificationStatus == .denied ? "通知已被系统关闭" : "尚未授权通知")
                    .font(.body)
                Spacer()
                if notificationStatus == .notDetermined {
                    Button("启用通知") {
                        Task {
                            await AppNotificationService.shared.requestAuthorization()
                            notificationStatus = await AppNotificationService.shared.authorizationStatus()
                        }
                    }.buttonStyle(.bordered)
                } else if notificationStatus == .denied {
                    Button("打开系统通知设置") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
                            NSWorkspace.shared.open(url)
                        }
                    }.buttonStyle(.bordered)
                }
            }
            SettingHint("通知只在任务开始、完成或失败时发送，详细进度仍可在 App 中查看。")
        }
    }
    #endif

    private func loadModels(_ settings: AppSettings) {
        isLoadingModels = true; modelLoadError = nil
        let provider = settings.aiProvider
        let baseURL = settings.llmBaseURL
        let apiKey = settings.llmAPIKey
        Task {
            do {
                let models = try await ModelCatalog.fetch(baseURL: baseURL, apiKey: apiKey, provider: provider)
                availableModels[provider] = models
                if provider == settings.aiProvider && !models.contains(settings.llmModel) {
                    settings.llmModel = models.contains(provider.defaultModel) ? provider.defaultModel : (models.first ?? settings.llmModel)
                }
            } catch { modelLoadError = error.localizedDescription }
            isLoadingModels = false
        }
    }
}

private struct SettingsGroup<Content: View>: View {
    let title: String; let subtitle: String; let icon: String
    @ViewBuilder let content: Content
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 15) {
                HStack(spacing: 10) {
                    Image(systemName: icon).foregroundStyle(AppTheme.accent).frame(width: 28, height: 28).background(AppTheme.accentMuted, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) { Text(title).font(.headline); Text(subtitle).font(.caption).foregroundStyle(AppTheme.secondaryText) }
                }
                Divider()
                content
            }
        }
    }
}

private struct SettingsTextField: View {
    let label: String; @Binding var text: String; let placeholder: String
    init(_ label: String, text: Binding<String>, placeholder: String) { self.label = label; self._text = text; self.placeholder = placeholder }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.caption.weight(.medium)).foregroundStyle(AppTheme.secondaryText)
            TextField(placeholder, text: $text).textFieldStyle(.roundedBorder).frame(maxWidth: 520)
        }
    }
}

private struct SettingHint: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View { Label(text, systemImage: "info.circle").font(.caption).foregroundStyle(AppTheme.secondaryText) }
}
