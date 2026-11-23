import SwiftUI
import os
import FlashNoteCore

let recorderLogger = Logger(subsystem: "com.flashnote.mac", category: "recorder")

/// 录音界面：REC 指示 + 计时 + 波形 + 实时转写 + 暂停/停止/完成。
struct RecorderView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appEnvironment) private var environment
    @State private var viewModel: RecorderViewModel?
    @State private var errorMessage: String?
    @AppStorage("liveTranscriptionLocale") private var liveTranscriptionLocale = "zh-CN"

    var body: some View {
        Group {
            if let viewModel {
                content(viewModel)
            } else if let errorMessage {
                errorView(errorMessage)
            } else {
                ProgressView("准备录音…")
            }
        }
        .frame(minWidth: 560, minHeight: 480)
        .task {
            // 视图层负责授权检查（语音识别 → 麦克风）；通过后创建 ViewModel 并立即开始录音
            recorderLogger.info("task begin")
            if let authError = await SpeechAuthorization.requestPermissions() {
                recorderLogger.error("speech auth failed: \(authError)")
                errorMessage = RecorderViewModel.errorText(for: authError)
                return
            }
            recorderLogger.info("speech authorized")
            if let micError = await SpeechAuthorization.requestMicrophonePermission() {
                recorderLogger.error("mic auth failed: \(micError)")
                errorMessage = RecorderViewModel.errorText(for: micError)
                return
            }
            recorderLogger.info("mic authorized")
            guard let vm = makeViewModel() else {
                recorderLogger.error("engine unavailable")
                errorMessage = "语音识别不可用"
                return
            }
            do {
                try vm.start()
                viewModel = vm
                if let id = vm.recordingID {
                    environment?.processing.beginTranscription(id, title: vm.recordingTitle)
                }
                recorderLogger.info("recording started")
            } catch {
                recorderLogger.error("start failed: \(String(describing: error), privacy: .public)")
                errorMessage = RecorderViewModel.errorText(for: error)
            }
        }
    }

    private func makeViewModel() -> RecorderViewModel? {
        guard let env = environment else { return nil }
        let engine = SpeechEngine(locale: Locale(identifier: liveTranscriptionLocale))
            ?? SpeechEngine(locale: Locale(identifier: "zh-CN"))
        guard let engine else { return nil }
        return RecorderViewModel(audio: AudioService(), engine: engine, store: env.store)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(AppTheme.secondaryText)
            Text(message)
                .foregroundStyle(AppTheme.primaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
            Button("关闭") { dismiss() }
                .buttonStyle(.borderedProminent)
        }
        .padding(24)
    }

    private func content(_ vm: RecorderViewModel) -> some View {
        VStack(spacing: 18) {
            header(vm)
            WaveformView(level: vm.level)
            Text(RecorderViewModel.formatElapsed(vm.elapsed))
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(AppTheme.primaryText)
            HStack(spacing: 8) {
                Label("实时转写", systemImage: "text.bubble")
                Text("·")
                Text(liveTranscriptionLocale == "en-US" ? "English" : "中文")
                Spacer()
                Text(vm.recordedBytes > 0
                     ? "本机已保存 \(ByteCountFormatter.string(fromByteCount: vm.recordedBytes, countStyle: .file))"
                     : "录音保存在本机")
            }
            .font(.caption).foregroundStyle(AppTheme.secondaryText)
            LiveTranscriptView(segments: vm.segments, partialText: vm.partialText)
                .frame(minHeight: 190)
            if let error = vm.errorMessage {
                Text(error).font(.caption).foregroundStyle(AppTheme.destructive)
            }
            controls(vm)
        }
        .padding(24)
    }

    private func header(_ vm: RecorderViewModel) -> some View {
        HStack {
            if vm.phase != .idle {
                Circle().fill(AppTheme.destructive).frame(width: 9, height: 9)
                Text(vm.phase == .paused ? "已暂停" : "正在录音")
                    .font(.headline)
            }
            Spacer()
            Text(vm.recordingTitle)
                .font(.subheadline)
                .foregroundStyle(AppTheme.secondaryText)
        }
    }

    private func controls(_ vm: RecorderViewModel) -> some View {
        HStack(spacing: 18) {
            if vm.phase == .recording {
                Button("暂停") {
                    vm.pause()
                }.buttonStyle(.bordered)
            } else if vm.phase == .paused {
                Button("继续") {
                    vm.resume()
                }.buttonStyle(.bordered)
            }
            Spacer()
            Button {
                vm.stop()
                if vm.errorMessage == nil {
                    if let id = vm.recordingID, !vm.segments.isEmpty {
                        environment?.processing.transcriptionCompleted(id)
                        Task { await environment?.processing.generateAll(recordingID: id) }
                    } else if let id = vm.recordingID {
                        environment?.processing.transcriptionFailed(id, error: TranscriptionError.engineFailed("未识别到语音"))
                    }
                    dismiss()
                } else if let id = vm.recordingID {
                    environment?.processing.transcriptionFailed(id, error: TranscriptionError.engineFailed(vm.errorMessage ?? "录音保存失败"))
                }
            } label: { Label("完成录音", systemImage: AppIcons.checkmark) }
                .buttonStyle(.borderedProminent)
            if vm.phase == .idle { Button("关闭") { dismiss() }.buttonStyle(.bordered) }
        }
        .padding(.top, 4)
    }
}

/// 圆形图标按钮。
struct IconButton: View {
    let icon: String
    var color: Color = .white
    var background: Color = AppTheme.accent
    var size: CGFloat = 46
    var showsBorder: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size * 0.38, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: size, height: size)
                .background(background, in: Circle())
                .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
        }
        .buttonStyle(.plain)
        .overlay {
            if showsBorder {
                Circle().stroke(AppTheme.border, lineWidth: 1)
            }
        }
    }
}
