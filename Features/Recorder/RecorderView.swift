import SwiftUI
import FlashNoteCore

/// 录音界面：REC 指示 + 计时 + 波形 + 实时转写 + 暂停/停止/完成。
struct RecorderView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appEnvironment) private var environment
    @State private var viewModel: RecorderViewModel?

    var body: some View {
        Group {
            if let viewModel {
                content(viewModel)
            } else {
                ProgressView("准备录音…")
            }
        }
        .frame(minWidth: 560, minHeight: 480)
        .task {
            // 视图层负责授权检查
            if let authError = await SpeechAuthorization.requestPermissions() {
                // M1：授权失败直接退出；后续里程碑做引导页
                showAuthError(authError)
                return
            }
            viewModel = makeViewModel()
        }
    }

    private func makeViewModel() -> RecorderViewModel {
        let env = environment
        let engine = SpeechEngine() ?? SpeechEngine(locale: Locale(identifier: "en-US"))!
        return RecorderViewModel(audio: AudioService(), engine: engine, store: env!.store)
    }

    private func content(_ vm: RecorderViewModel) -> some View {
        VStack(spacing: 20) {
            header(vm)
            WaveformView(level: vm.level)
            Text(RecorderViewModel.formatElapsed(vm.elapsed))
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(AppTheme.primaryText)
            LiveTranscriptView(segments: vm.segments, partialText: vm.partialText)
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
        HStack(spacing: 28) {
            if vm.phase == .recording {
                IconButton(icon: AppIcons.pause, color: AppTheme.primaryText, background: AppTheme.background) {
                    vm.pause()
                }
            } else if vm.phase == .paused {
                IconButton(icon: AppIcons.play, color: .white, background: AppTheme.accent) {
                    vm.resume()
                }
            }
            IconButton(icon: AppIcons.stop, color: .white, background: AppTheme.destructive, size: 52) {
                vm.stop()
                dismiss()
            }
            IconButton(icon: AppIcons.checkmark, color: .white, background: AppTheme.accent) {
                vm.stop()
                dismiss()
            }
        }
        .padding(.top, 4)
    }

    private func showAuthError(_ error: TranscriptionError) {
        dismiss()
    }
}

/// 圆形图标按钮。
struct IconButton: View {
    let icon: String
    var color: Color = .white
    var background: Color = AppTheme.accent
    var size: CGFloat = 46
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
    }
}
