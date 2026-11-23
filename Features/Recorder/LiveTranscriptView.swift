import SwiftUI
import FlashNoteCore

/// 实时转写面板：定稿段落列表 + 当前局部文本。
struct LiveTranscriptView: View {
    let segments: [TranscriptSegment]
    let partialText: String?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if segments.isEmpty && (partialText?.isEmpty ?? true) {
                        ContentUnavailableView("正在聆听", systemImage: "waveform", description: Text("识别出的文字会实时显示在这里，完成录音后保存在全文中。"))
                            .frame(maxWidth: .infinity, minHeight: 150)
                    }
                    ForEach(segments) { segment in
                        HStack(alignment: .top, spacing: 12) {
                            Text(AudioPlayer.formatTime(segment.startTime))
                                .font(.caption.monospacedDigit()).foregroundStyle(AppTheme.secondaryText)
                            Text(LiveTranscriptSegmenter.lines(segment.text).joined(separator: "\n"))
                                .font(.body)
                                .lineSpacing(6)
                                .foregroundStyle(AppTheme.primaryText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }.id(segment.id)
                    }
                    if let partialText, !partialText.isEmpty {
                        Text(LiveTranscriptSegmenter.lines(partialText).joined(separator: "\n"))
                            .font(.body)
                            .lineSpacing(6)
                            .foregroundStyle(AppTheme.primaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id("partial")
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: segments.count) { _, _ in
                withAnimation { proxy.scrollTo(segments.last?.id, anchor: .bottom) }
            }
            .onChange(of: partialText) { _, _ in
                withAnimation { proxy.scrollTo("partial", anchor: .bottom) }
            }
        }
        .background(AppTheme.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(AppTheme.border, lineWidth: 1)
        }
    }
}
