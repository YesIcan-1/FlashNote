import SwiftUI
import FlashNoteCore

/// 设置页：转写引擎选择 + LLM 连接配置。
struct SettingsView: View {
    @Environment(\.appEnvironment) private var environment
    @State private var settings: AppSettings?

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

            Section("LLM 连接（云端转写与 AI 纪要共用）") {
                TextField("Base URL", text: Binding(
                    get: { settings.llmBaseURL },
                    set: { settings.llmBaseURL = $0 }
                ))
                TextField("模型", text: Binding(
                    get: { settings.llmModel },
                    set: { settings.llmModel = $0 }
                ))
                SecureField("API Key", text: Binding(
                    get: { settings.llmAPIKey },
                    set: { settings.llmAPIKey = $0 }
                ))
            }
        }
        .formStyle(.grouped)
        .padding(20)
    }
}
