import Foundation

public enum RecordingTitle {
    /// 只有纪要给出了明确主题时才改名，避免把“未明确”写成录音名称。
    public static func shortTitle(from minutes: Minutes) -> String? {
        guard let section = minutes.sections.first(where: { ["会议主题", "议题", "访谈主题", "讨论目标", "项目目标", "知识点", "结论"].contains($0.title) }) else { return nil }
        let cleaned = cleanedFirstLine(section.body)
        var phrase = cleaned.components(separatedBy: CharacterSet(charactersIn: "，,。；;：:、")).first ?? cleaned
        for prefix in ["本次会议围绕", "会议围绕", "围绕", "关于"] where phrase.hasPrefix(prefix) {
            phrase.removeFirst(prefix.count)
            break
        }
        phrase = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !phrase.isEmpty, phrase != "未明确", phrase != "无", phrase != "未提及" else { return nil }
        return String(phrase.prefix(20))
    }

    private static func cleanedFirstLine(_ body: String) -> String {
        let firstLine = body.components(separatedBy: .newlines).first ?? ""
        return firstLine
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "__", with: "")
            .replacingOccurrences(of: "^[\\s\\-*•#0-9.、]+", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "。；;，,"))
    }

    /// 补齐旧版设备时间戳名称，并修正旧版自动生成后截断在词中间的标题。
    /// 只处理可确认由应用自动生成的名称，避免覆盖用户自定义标题。
    @discardableResult
    public static func backfillHardwareTitles(in store: RecordingStore) throws -> Int {
        var changed = 0
        for var recording in try store.fetchRecordings() {
            guard recording.status != .recording else { continue }
            let minutes = try store.fetchMinutes(recordingID: recording.id)
            guard let latest = minutes.last(where: { $0.templateID != MinutesTemplate.mindMap.id && $0.templateID != MinutesTemplate.insight.id }),
                  let title = shortTitle(from: latest) else { continue }
            let oldGeneratedTitle = latest.sections.first(where: { ["会议主题", "议题", "访谈主题", "讨论目标", "项目目标", "知识点", "结论"].contains($0.title) })
                .map { section in
                    let cleaned = cleanedFirstLine(section.body)
                    let phrase = cleaned.components(separatedBy: CharacterSet(charactersIn: "，,。；;：:")).first ?? cleaned
                    return String(phrase.prefix(20))
                }
            let isHardwareName = recording.title.range(of: #"^note\d{8}-\d{6}$"#, options: .regularExpression) != nil
            guard isHardwareName || recording.title == oldGeneratedTitle else { continue }
            guard recording.title != title else { continue }
            recording.title = title
            recording.markSummarized()
            try store.upsertRecording(recording)
            changed += 1
        }
        return changed
    }
}
