import Foundation
import FlashNoteCore

enum DeviceError: Error, Equatable {
    case downloadCode(UInt8)
}

/// 设备文件 → 下载 WAV → 转写 → 保存 Transcript 的编排器。
@Observable
final class DeviceTranscriptionService {
    private let device: CB08Device
    private let engine: FileTranscriptionEngine
    private let store: RecordingStore
    private let storeDirectory: URL

    private(set) var progress: Double = 0
    private(set) var statusText = ""

    init(device: CB08Device, engine: FileTranscriptionEngine, store: RecordingStore, storeDirectory: URL = AppEnvironment.defaultStoreDirectory()) {
        self.device = device
        self.engine = engine
        self.store = store
        self.storeDirectory = storeDirectory
    }

    /// 下载设备文件并转写保存。
    func downloadAndTranscribe(file: CB08FileEntry, title: String) async throws -> Transcript {
        let (data, actualName) = try await download(file: file)

        let id = UUID()
        let audioDir = storeDirectory.appendingPathComponent("audio", isDirectory: true)
        try FileManager.default.createDirectory(at: audioDir, withIntermediateDirectories: true)
        let dest = audioDir.appendingPathComponent("\(id.uuidString).wav")
        try data.write(to: dest)

        statusText = "转写中…"
        let segments = try await engine.transcribe(audioFileURL: dest, language: "zh")
        let transcript = Transcript(recordingID: id, segments: segments, language: "zh")

        var recording = Recording(id: id, title: title.isEmpty ? actualName : title)
        recording.audioFilename = dest.lastPathComponent
        recording.markTranscribed()
        try store.upsertRecording(recording)
        try store.upsertTranscript(transcript)
        statusText = "完成"
        return transcript
    }

    /// 异步下载（候选名回退：base.wav → base.opus → 原始名）。
    private func download(file: CB08FileEntry) async throws -> (Data, String) {
        let candidates = file.candidateNames
        var lastError: Error = DeviceError.downloadCode(0)
        for (index, name) in candidates.enumerated() {
            do {
                progress = 0
                return try await downloadOne(name: name)
            } catch let error as DeviceError {
                lastError = error
                if error != .downloadCode(1) { throw error } // code=1 才换候选名
                _ = index
            }
        }
        throw lastError
    }

    private func downloadOne(name: String) async throws -> (Data, String) {
        try await withCheckedThrowingContinuation { cont in
            var buffer = Data()
            device.onDownloadData = { [weak self] d in
                buffer.append(d)
                self?.statusText = "下载中…"
            }
            device.onDownloadComplete = { [weak self] data, actualName in
                self?.statusText = "下载完成"
                cont.resume(returning: (data, actualName))
            }
            device.onDownloadCode = { code in
                if code != 0 {
                    cont.resume(throwing: DeviceError.downloadCode(code))
                }
            }
            device.requestImport(filename: name)
        }
    }
}
