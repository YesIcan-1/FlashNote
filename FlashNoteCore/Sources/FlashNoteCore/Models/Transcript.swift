import Foundation

/// 转写的一个段落（时间戳 + 可选说话人 + 文本）。
public struct TranscriptSegment: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var startTime: TimeInterval
    public var endTime: TimeInterval?
    public var speaker: String?
    public var text: String
    public var isFinal: Bool

    public init(
        id: UUID = UUID(),
        startTime: TimeInterval,
        endTime: TimeInterval? = nil,
        speaker: String? = nil,
        text: String,
        isFinal: Bool = true
    ) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.speaker = speaker
        self.text = text
        self.isFinal = isFinal
    }
}

/// 一次录音的完整转写（段落集合）。
public struct Transcript: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var recordingID: UUID
    public var segments: [TranscriptSegment]
    public var language: String
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        recordingID: UUID,
        segments: [TranscriptSegment] = [],
        language: String = "zh-Hans",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.recordingID = recordingID
        self.segments = segments
        self.language = language
        self.createdAt = createdAt
    }

    /// 全部段落文本，以换行连接（作为 LLM 输入）。
    public var fullText: String {
        segments.map(\.text).joined(separator: "\n")
    }

    public mutating func append(_ segment: TranscriptSegment) {
        segments.append(segment)
    }
}
