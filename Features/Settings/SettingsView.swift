import SwiftUI
import FlashNoteCore

/// 设置页：转写引擎选择 + LLM 连接配置。
struct SettingsView: View {
    @Environment(\.appEnvironment) private var environment
    @State private var settings: AppSettings?
    @State private var availableModels: [String] = []
    @State private var modelLoadError: String?
    @State private var isLoadingModels = false

    var body: some View {
        Group {
            if let settings {
                form(settings)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("设置")
        .onAppear {
            if settings == nil {
                settings = AppSettings(storeDirectory: AppEnvironment.defaultStoreDirectory())
            }
        }
    }

    private func form(_ settings: AppSettings) -> some View {
        Form {
            Section("外观") {
                Picker("显示模式", selection: Binding(
                    get: { settings.appearanceMode },
                    set: { settings.appearanceMode = $0 }
                )) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
            }
            Section("转写引擎") {
                Picker("导入音频转写", selection: Binding(
                    get: { settings.transcriptionEngine },
                    set: { settings.transcriptionEngine = $0 }
                )) {
                    ForEach(TranscriptionEngineChoice.allCases) { choice in
                        Text(choice.displayName).tag(choice)
                    }
                }
                if settings.transcriptionEngine == .whisperKit {
                    Text("本地 WhisperKit 首次转写时会下载模型（约数百 MB）")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                }
            }

            Section("API 设置（云端转写与 AI 纪要共用）") {
                TextField("Base URL", text: Binding(
                    get: { settings.llmBaseURL },
                    set: { settings.llmBaseURL = $0 }
                ))
                TextField("模型", text: Binding(
                    get: { settings.llmModel },
                    set: { settings.llmModel = $0 }
                ))
                if !availableModels.isEmpty {
                    Picker("已识别模型", selection: Binding(
                        get: { settings.llmModel },
                        set: { settings.llmModel = $0 }
                    )) {
                        ForEach(availableModels, id: \.self) { Text($0).tag($0) }
                    }
                }
                SecureField("API Key", text: Binding(
                    get: { settings.llmAPIKey },
                    set: { settings.llmAPIKey = $0 }
                ))
                Button(isLoadingModels ? "正在识别模型…" : "识别可用模型") { loadModels(settings) }
                    .disabled(isLoadingModels || settings.llmAPIKey.isEmpty)
                if let modelLoadError { Text(modelLoadError).font(.caption).foregroundStyle(AppTheme.destructive) }
            }
        }
        .formStyle(.grouped)
        .padding(20)
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
