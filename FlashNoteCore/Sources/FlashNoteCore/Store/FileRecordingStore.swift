import Foundation

/// JSON 文件实现的本地存储。每个实体一个文件：{kind}-{id}.json。
public final class FileRecordingStore: RecordingStore, @unchecked Sendable {
    private let root: URL
    private let lock = NSLock()
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(root: URL) throws {
        self.root = root
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        // 不设置自定义日期策略（保持默认 deferredToDate，参考日期 Double 编码）。
        // 实测（本机 CLT Foundation）：.iso8601 与 .secondsSince1970/.millisecondsSince1970
        // 都会损坏亚秒精度，导致 Date() 生成的戳 encode→decode 后不相等；默认策略 0/50000 失败。
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder
        let decoder = JSONDecoder()
        self.decoder = decoder
    }

    private func url(kind: String, id: UUID) -> URL {
        root.appendingPathComponent("\(kind)-\(id.uuidString).json")
    }

    private func load<T: Decodable>(_ type: T.Type, kind: String, id: UUID) throws -> T? {
        let file = url(kind: kind, id: id)
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        do {
            let data = try Data(contentsOf: file)
            return try decoder.decode(T.self, from: data)
        } catch {
            throw StoreError.corrupted(kind)
        }
    }

    private func save<T: Encodable>(_ value: T, kind: String, id: UUID) throws {
        let data = try encoder.encode(value)
        try data.write(to: url(kind: kind, id: id), options: .atomic)
    }

    public func fetchRecordings() throws -> [Recording] {
        lock.lock(); defer { lock.unlock() }
        let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        var result: [Recording] = []
        for file in files where file.lastPathComponent.hasPrefix("recording-") {
            do {
                let data = try Data(contentsOf: file)
                result.append(try decoder.decode(Recording.self, from: data))
            } catch {
                throw StoreError.corrupted("recording")
            }
        }
        return result.sorted { $0.createdAt > $1.createdAt }
    }

    public func fetchRecording(id: UUID) throws -> Recording? {
        lock.lock(); defer { lock.unlock() }
        return try load(Recording.self, kind: "recording", id: id)
    }

    public func upsertRecording(_ recording: Recording) throws {
        lock.lock(); defer { lock.unlock() }
        try save(recording, kind: "recording", id: recording.id)
    }

    public func deleteRecording(id: UUID) throws {
        lock.lock(); defer { lock.unlock() }
        try FileManager.default.removeItem(at: url(kind: "recording", id: id))
    }

    public func fetchTranscript(recordingID: UUID) throws -> Transcript? {
        lock.lock(); defer { lock.unlock() }
        return try load(Transcript.self, kind: "transcript", id: recordingID)
    }

    public func upsertTranscript(_ transcript: Transcript) throws {
        lock.lock(); defer { lock.unlock() }
        try save(transcript, kind: "transcript", id: transcript.recordingID)
    }

    /// 录音的全部纪要（含历史版本，按生成时间升序）。文件按 minutes.id 键控，
    /// 同录音多份纪要并存（规格 §5.4 风格切换保留旧纪要）。
    public func fetchMinutes(recordingID: UUID) throws -> [Minutes] {
        lock.lock(); defer { lock.unlock() }
        let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        var result: [Minutes] = []
        for file in files where file.lastPathComponent.hasPrefix("minutes-") {
            do {
                let data = try Data(contentsOf: file)
                let minutes = try decoder.decode(Minutes.self, from: data)
                if minutes.recordingID == recordingID {
                    result.append(minutes)
                }
            } catch {
                throw StoreError.corrupted("minutes")
            }
        }
        return result.sorted { $0.generatedAt < $1.generatedAt }
    }

    public func upsertMinutes(_ minutes: Minutes) throws {
        lock.lock(); defer { lock.unlock() }
        try save(minutes, kind: "minutes", id: minutes.id)
    }

    public func fetchFolders() throws -> [Folder] {
        lock.lock(); defer { lock.unlock() }
        let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        var result: [Folder] = []
        for file in files where file.lastPathComponent.hasPrefix("folder-") {
            do {
                let data = try Data(contentsOf: file)
                result.append(try decoder.decode(Folder.self, from: data))
            } catch {
                throw StoreError.corrupted("folder")
            }
        }
        return result.sorted { $0.createdAt < $1.createdAt }
    }

    public func upsertFolder(_ folder: Folder) throws {
        lock.lock(); defer { lock.unlock() }
        try save(folder, kind: "folder", id: folder.id)
    }
}
