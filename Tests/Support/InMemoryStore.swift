import Foundation
import FlashNoteCore

/// RecordingStore 内存实现（测试替身）。
final class InMemoryStore: RecordingStore {
    private var recordings: [UUID: Recording] = [:]
    private var transcripts: [UUID: Transcript] = [:]
    private var minutes: [UUID: [Minutes]] = [:]
    private var folders: [UUID: Folder] = [:]

    func fetchRecordings() throws -> [Recording] {
        recordings.values.sorted { $0.createdAt > $1.createdAt }
    }
    func fetchRecording(id: UUID) throws -> Recording? { recordings[id] }
    func upsertRecording(_ recording: Recording) throws { recordings[recording.id] = recording }
    func deleteRecording(id: UUID) throws { recordings[id] = nil }
    func fetchTranscript(recordingID: UUID) throws -> Transcript? { transcripts[recordingID] }
    func upsertTranscript(_ transcript: Transcript) throws { transcripts[transcript.recordingID] = transcript }
    func fetchMinutes(recordingID: UUID) throws -> [Minutes] { minutes[recordingID] ?? [] }
    func upsertMinutes(_ minutes: Minutes) throws { self.minutes[minutes.recordingID, default: []].append(minutes) }
    func fetchFolders() throws -> [Folder] { folders.values.sorted { $0.createdAt < $1.createdAt } }
    func upsertFolder(_ folder: Folder) throws { folders[folder.id] = folder }
}
