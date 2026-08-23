import SwiftUI
import FlashNoteCore

/// 实时转写面板：定稿段落列表 + 当前局部文本高亮。
struct LiveTranscriptView: View {
    let segments: [TranscriptSegment]
    let partialText: String?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(segments) { segment in
                        Text(segment.text)
                            .font(.callout)
                            .foregroundStyle(AppTheme.primaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(segment.id)
                    }
                    if let partialText, !partialText.isEmpty {
                        Text(partialText)
                            .font(.callout.weight(.medium))
                            .foregroundStyle(AppTheme.accent)
                            .padding(10)
                            .background(AppTheme.infoBackground, in: RoundedRectangle(cornerRadius: 8))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id("partial")
                    }
                }
                .padding(12)
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
