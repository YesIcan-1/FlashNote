import SwiftUI
import FlashNoteCore

/// 设置页以产品分区组织，避免系统 Form 将模型和设备操作混在一处。
struct SettingsView: View {
    @Environment(\.appEnvironment) private var environment
    @State private var settings: AppSettings?
    @State private var availableModels: [String] = []
    @State private var modelLoadError: String?
    @State private var isLoadingModels = false
    @State private var didClearRememberedDevice = false

    var body: some View {
        Group {
            if let settings { content(settings) }
            else { ProgressView("正在读取设置…") }
        }
        .navigationTitle("设置")
        .onAppear { if settings == nil { settings = AppSettings(storeDirectory: AppEnvironment.defaultStoreDirectory()) } }
    }

    private func content(_ settings: AppSettings) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                transcriptionGroup(settings)
                minutesGroup(settings)
                qwenGroup(settings)
                deviceGroup
            }
            .padding(.horizontal, 28).padding(.vertical, 24)
            .frame(maxWidth: 900, alignment: .leading)
        }
        .background(AppTheme.pageBackground)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("设置").font(.system(size: 30, weight: .bold, design: .rounded))
            Text("仅在这里管理模型和设备偏好。不会要求本机密码。")
                .font(.subheadline).foregroundStyle(AppTheme.secondaryText)
        }
    }

    private func transcriptionGroup(_ settings: AppSettings) -> some View {
        SettingsGroup(title: "全文转写", subtitle: "导入音频和下载设备文件使用此默认引擎", icon: "waveform") {
            Picker("默认转写引擎", selection: Binding(get: { settings.transcriptionEngine }, set: { settings.transcriptionEngine = $0 })) {
                ForEach(TranscriptionEngineChoice.allCases) { choice in Text(choice.displayName).tag(choice) }
            }
            .pickerStyle(.segmented).frame(maxWidth: 440)
            if settings.transcriptionEngine == .whisperKit {
                SettingHint("本地 WhisperKit 首次使用会下载模型；没有网络时仍可使用已下载的模型。")
            } else {
                SettingHint("Qwen3-ASR 的长文件上传配置在下方“云端转写”中；未配置时会明确提示，不会生成空全文。")
            }
        }
    }

    private func minutesGroup(_ settings: AppSettings) -> some View {
        SettingsGroup(title: "AI 纪要", subtitle: "DeepSeek 或兼容 OpenAI 的服务，只根据真实全文生成纪要", icon: AppIcons.sparkle) {
            SettingsTextField("API 地址", text: Binding(get: { settings.llmBaseURL }, set: { settings.llmBaseURL = $0 }), placeholder: "https://api.deepseek.com")
            if availableModels.isEmpty {
                SettingsTextField("模型", text: Binding(get: { settings.llmModel }, set: { settings.llmModel = $0 }), placeholder: "deepseek-chat")
            } else {
                Picker("模型", selection: Binding(get: { settings.llmModel }, set: { settings.llmModel = $0 })) {
                    ForEach(availableModels, id: \.self) { Text($0).tag($0) }
                }
                .frame(maxWidth: 520, alignment: .leading)
            }
            SecureField("API Key", text: Binding(get: { settings.llmAPIKey }, set: { settings.llmAPIKey = $0 }))
                .textFieldStyle(.roundedBorder).frame(maxWidth: 520)
            HStack(spacing: 10) {
                Button(isLoadingModels ? "正在识别模型…" : "识别可用模型") { loadModels(settings) }
                    .buttonStyle(.bordered).disabled(isLoadingModels || settings.llmAPIKey.isEmpty)
                if let modelLoadError { Text(modelLoadError).font(.caption).foregroundStyle(AppTheme.destructive) }
            }
        }
    }

    private func qwenGroup(_ settings: AppSettings) -> some View {
        SettingsGroup(title: "云端转写", subtitle: "Qwen3-ASR 用于设备文件与实时转写；与 AI 纪要服务独立", icon: "cloud") {
            SecureField("DashScope API Key", text: Binding(get: { settings.qwenASRAPIKey }, set: { settings.qwenASRAPIKey = $0 }))
                .textFieldStyle(.roundedBorder).frame(maxWidth: 520)
            SettingsTextField("Workspace ID", text: Binding(get: { settings.qwenASRWorkspaceID }, set: { settings.qwenASRWorkspaceID = $0 }), placeholder: "长文件转写需要")
            SettingsTextField("文件模型", text: Binding(get: { settings.qwenASRFileModel }, set: { settings.qwenASRFileModel = $0 }), placeholder: "qwen3-asr-flash-filetrans")
            SettingsTextField("实时模型", text: Binding(get: { settings.qwenASRRealtimeModel }, set: { settings.qwenASRRealtimeModel = $0 }), placeholder: "qwen3-asr-realtime")
            SettingHint("长录音需要临时上传签名服务后才能使用云端链路；该服务不会把 OSS 长期密钥放进 App。")
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

    private func loadModels(_ settings: AppSettings) {
        isLoadingModels = true; modelLoadError = nil
        Task {
            do {
                availableModels = try await ModelCatalog.fetch(baseURL: settings.llmBaseURL, apiKey: settings.llmAPIKey)
                if availableModels.contains("deepseek-chat") { settings.llmModel = "deepseek-chat" }
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
