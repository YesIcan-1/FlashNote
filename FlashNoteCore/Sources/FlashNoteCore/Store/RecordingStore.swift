import Foundation

public enum StoreError: Error, Equatable {
    case corrupted(String)
}

/// 数据访问抽象。App 层后续提供 CloudKit 实现，UI 无感知。
public protocol RecordingStore: AnyObject, Sendable {
    func fetchRecordings() throws -> [Recording]
    func fetchRecording(id: UUID) throws -> Recording?
    func upsertRecording(_ recording: Recording) throws
    func deleteRecording(id: UUID) throws

    func fetchTranscript(recordingID: UUID) throws -> Transcript?
    func upsertTranscript(_ transcript: Transcript) throws

    /// 录音的全部纪要（含历史版本，按生成时间升序；规格 §5.4 保留旧纪要）。
    func fetchMinutes(recordingID: UUID) throws -> [Minutes]
    func upsertMinutes(_ minutes: Minutes) throws

    func fetchFolders() throws -> [Folder]
    func upsertFolder(_ folder: Folder) throws
}
