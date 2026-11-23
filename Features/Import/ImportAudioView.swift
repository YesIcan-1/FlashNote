import SwiftUI
import FlashNoteCore
import UniformTypeIdentifiers

/// 导入音频并转写。
struct ImportAudioView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appEnvironment) private var environment
    @State private var showingImporter = false
    @State private var viewModel: ImportTranscriptionViewModel?
    @State private var statusText = "选择音频或视频文件开始导入转写"
    @State private var isWorking = false
    @State private var activeRecordingID: UUID?

    var body: some View {
        VStack(spacing: 16) {
            Text("导入音视频转写")
                .font(.title3.bold())
            Text(statusText)
                .foregroundStyle(AppTheme.secondaryText)
                .multilineTextAlignment(.center)
            if let activeRecordingID, let progress = environment?.processing.progress[activeRecordingID] {
                HStack(spacing: 8) {
                    if progress.isActive { TaskProgressRing(fraction: progress.fraction, label: progress.stage.rawValue) }
                    Text(progress.stage.rawValue)
                }.font(.caption).foregroundStyle(AppTheme.secondaryText)
                if let detail = progress.detail { Text(detail).font(.caption).foregroundStyle(AppTheme.secondaryText) }
            } else if isWorking {
                ProgressView()
            }
            Button("选择音视频文件") {
                showingImporter = true
            }
            .buttonStyle(.borderedProminent)
            .disabled(isWorking)
            if !isWorking, activeRecordingID != nil {
                Button("完成") { dismiss() }.buttonStyle(.bordered)
            }
        }
        .padding(24)
        .frame(minWidth: 420, minHeight: 220)
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.audio, .movie],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                guard !urls.isEmpty else { return }
                Task { await importAndTranscribe(urls) }
            case .failure(let error):
                statusText = "导入失败：\(error.localizedDescription)"
            }
        }
    }

    private func importAndTranscribe(_ urls: [URL]) async {
        guard let env = environment else { return }
        isWorking = true
        statusText = urls.count == 1 ? "转写中…" : "正在处理 1 / \(urls.count)…"
        let settings = AppSettings(storeDirectory: AppEnvironment.defaultStoreDirectory())
        let engine = FileTranscriptionEngineFactory.make(settings: settings)
        let vm = ImportTranscriptionViewModel(store: env.store, engine: engine)
        viewModel = vm
        do {
            for (index, url) in urls.enumerated() {
                statusText = urls.count == 1 ? "转写中…" : "正在处理 \(index + 1) / \(urls.count)…"
                do {
                    let recording = try await vm.importAndTranscribe(sourceURL: url, title: url.deletingPathExtension().lastPathComponent) { id in
                        activeRecordingID = id
                        env.processing.beginTranscription(id)
                    }
                    env.processing.transcriptionCompleted(recording.id)
                    await env.processing.generateAll(recordingID: recording.id)
                } catch {
                    if let activeRecordingID { env.processing.transcriptionFailed(activeRecordingID, error: error) }
                    throw error
                }
            }
            statusText = urls.count == 1 ? "文件处理已结束" : "已处理 \(urls.count) 个文件"
            if let activeRecordingID, environment?.processing.progress[activeRecordingID]?.stage == .completed {
                try? await Task.sleep(nanoseconds: 600_000_000)
                dismiss()
            }
        } catch {
            statusText = "转写失败：\(error.localizedDescription)"
        }
        isWorking = false
    }
}
