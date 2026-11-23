import SwiftUI

/// 显示 AI 返回的 Markdown 行内格式、标题与条目，避免把 **强调** 原样展示。
struct MarkdownBodyView: View {
    let source: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(Array(source.components(separatedBy: .newlines).enumerated()), id: \.offset) { _, raw in
                let line = raw.trimmingCharacters(in: .whitespaces)
                if line.isEmpty {
                    Spacer().frame(height: 3)
                } else if line.hasPrefix("#") {
                    inline(line.trimmingCharacters(in: CharacterSet(charactersIn: "# ")))
                        .font(.subheadline.weight(.semibold))
                        .textSelection(.enabled)
                } else if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("• ") {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•").foregroundStyle(AppTheme.accent)
                        inline(String(line.dropFirst(2))).textSelection(.enabled)
                    }.padding(.leading, CGFloat(raw.prefix { $0 == " " }.count) * 6)
                } else {
                    inline(line).textSelection(.enabled)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func inline(_ text: String) -> Text {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return Text((try? AttributedString(markdown: text, options: options)) ?? AttributedString(text))
    }
}
