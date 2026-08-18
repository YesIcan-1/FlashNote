import SwiftUI
import FlashNoteCore
import UniformTypeIdentifiers

/// 导入音频并转写。
struct ImportAudioView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appEnvironment) private var environment
    @State private var showingImporter = false
    @State private var viewModel: ImportTranscriptionViewModel?
    @State private var statusText = "选择音频文件开始导入转写"
    @State private var isWorking = false

    var body: some View {
        VStack(spacing: 16) {
            Text("导入音频转写")
                .font(.title3.bold())
            Text(statusText)
                .foregroundStyle(AppTheme.secondaryText)
                .multilineTextAlignment(.center)
            if isWorking {
                ProgressView()
            }
            Button("选择音频文件") {
                showingImporter = true
            }
            .buttonStyle(.borderedProminent)
            .disabled(isWorking)
        }
        .padding(24)
        .frame(minWidth: 420, minHeight: 220)
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                Task { await importAndTranscribe(url) }
            case .failure(let error):
                statusText = "导入失败：\(error.localizedDescription)"
            }
        }
    }

    private func importAndTranscribe(_ url: URL) async {
        guard let env = environment else { return }
        isWorking = true
        statusText = "转写中…"
        let settings = AppSettings(storeDirectory: AppEnvironment.defaultStoreDirectory())
        let engine = FileTranscriptionEngineFactory.make(settings: settings)
        let vm = ImportTranscriptionViewModel(store: env.store, engine: engine)
        viewModel = vm
        do {
            try await vm.importAndTranscribe(sourceURL: url, title: url.deletingPathExtension().lastPathComponent)
            statusText = "转写完成"
            try? await Task.sleep(nanoseconds: 600_000_000)
            dismiss()
        } catch {
            statusText = "转写失败：\(error.localizedDescription)"
        }
        isWorking = false
    }
}
