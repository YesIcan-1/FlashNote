import Foundation

/// 录音的流转状态。
public enum RecordingStatus: String, Codable, Sendable {
    case recording
    case transcribed
    case summarized
}

/// 一条录音记录（结构化数据；音频文件本身由 App 层存放于 iCloud Drive）。
public struct Recording: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var folderID: UUID?
    public var audioFilename: String?
    public var sourceDeviceName: String?
    public var duration: TimeInterval
    public var status: RecordingStatus
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        title: String,
        folderID: UUID? = nil,
        audioFilename: String? = nil,
        sourceDeviceName: String? = nil,
        duration: TimeInterval = 0,
        status: RecordingStatus = .recording,
        createdAt: Date = Date(),
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.folderID = folderID
        self.audioFilename = audioFilename
        self.sourceDeviceName = sourceDeviceName
        self.duration = duration
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
    }

    public mutating func markTranscribed() {
        status = .transcribed
        updatedAt = Date()
    }

    public mutating func markSummarized() {
        status = .summarized
        updatedAt = Date()
    }
}
