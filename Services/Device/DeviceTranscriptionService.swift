import Foundation
import FlashNoteCore

enum DeviceError: Error, Equatable {
    case downloadCode(UInt8)
    case incompleteDownload
}

/// 设备文件 → 可恢复下载 → 转写 → 保存 Transcript 的编排器。
@Observable
final class DeviceTranscriptionService {
    private let device: CB08Device
    private let engine: FileTranscriptionEngine
    private let store: RecordingStore
    private let storeDirectory: URL
    private let idleTimeoutNanoseconds: UInt64

    var onProgress: ((Double, String) -> Void)?
    private(set) var progress: Double = 0
    private(set) var statusText = ""

    init(device: CB08Device, engine: FileTranscriptionEngine, store: RecordingStore, storeDirectory: URL = AppEnvironment.defaultStoreDirectory(), idleTimeoutNanoseconds: UInt64 = 12_000_000_000) {
        self.device = device
        self.engine = engine
        self.store = store
        self.storeDirectory = storeDirectory
        self.idleTimeoutNanoseconds = idleTimeoutNanoseconds
    }

    /// 从上次接收位置恢复设备下载。音频分片直接写临时文件，避免长录音完整驻留内存。
    func downloadAndTranscribe(file: CB08FileEntry, title: String) async throws -> Transcript {
        expectedSize = max(1, file.size)
        progress = 0
        onProgress?(0, "准备下载…")

        let (downloadedURL, actualName) = try await download(file: file)
        let id = UUID()
        let audioDir = storeDirectory.appendingPathComponent("audio", isDirectory: true)
        try FileManager.default.createDirectory(at: audioDir, withIntermediateDirectories: true)
        let destination = audioDir.appendingPathComponent("\(id.uuidString).wav")
        if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
        try FileManager.default.moveItem(at: downloadedURL, to: destination)

        statusText = "转写中…"
        onProgress?(1, statusText)
        let segments = try await engine.transcribe(audioFileURL: destination, language: "zh")
        let transcript = Transcript(recordingID: id, segments: segments, language: "zh")

        var recording = Recording(id: id, title: title.isEmpty ? actualName : title)
        recording.audioFilename = destination.lastPathComponent
        recording.markTranscribed()
        try store.upsertRecording(recording)
        try store.upsertTranscript(transcript)
        statusText = "完成"
        return transcript
    }

    private func download(file: CB08FileEntry) async throws -> (URL, String) {
        var lastError: Error = DeviceError.downloadCode(0)
        for name in preferredDownloadCandidates(for: file) {
            let partialURL = partialFileURL(file: file, candidate: name)
            do {
                progress = 0
                let actualName = try await downloadOne(name: name, partialURL: partialURL)
                if actualName.lowercased().hasSuffix(".opus") {
                    statusText = "正在解码为 WAV…"
                    onProgress?(1, statusText)
                    do {
                        let wav = try CB08OpusFileDecoder.decodeToWAV(Data(contentsOf: partialURL))
                        try wav.write(to: partialURL, options: .atomic)
                    } catch {
                        try? FileManager.default.removeItem(at: partialURL)
                        lastError = error
                        continue
                    }
                }
                return (partialURL, actualName)
            } catch let error as DeviceError {
                lastError = error
                // 仅在尚未收到数据且设备明确报告不存在时，才切换候选名。
                if error == .downloadCode(1), partialSize(at: partialURL) == 0 {
                    try? FileManager.default.removeItem(at: partialURL)
                    continue
                }
                throw error
            }
        }
        throw lastError
    }

    private func preferredDownloadCandidates(for file: CB08FileEntry) -> [String] {
        let candidates = file.candidateNames
        let opus = candidates.filter { $0.lowercased().hasSuffix(".opus") }
        let wav = candidates.filter { $0.lowercased().hasSuffix(".wav") }
        let raw = candidates.filter { !$0.lowercased().hasSuffix(".opus") && !$0.lowercased().hasSuffix(".wav") }
        return Array(NSOrderedSet(array: wav + opus + raw)) as? [String] ?? candidates
    }

    private var expectedSize: UInt32 = 0
    private func downloadOne(name: String, partialURL: URL) async throws -> String {
        let manager = FileManager.default
        try manager.createDirectory(at: partialURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !manager.fileExists(atPath: partialURL.path) { manager.createFile(atPath: partialURL.path, contents: nil) }
        let offset = UInt32(min(partialSize(at: partialURL), Int64(UInt32.max)))
        let handle = try FileHandle(forWritingTo: partialURL)
        try handle.seekToEnd()
        var receivedThisAttempt: Int64 = 0
        reportProgress(totalReceived: Int64(offset))

        return try await withCheckedThrowingContinuation { continuation in
            var finished = false
            var idleTask: Task<Void, Never>?

            func finish(_ result: Result<String, Error>) {
                guard !finished else { return }
                finished = true
                idleTask?.cancel()
                try? handle.close()
                continuation.resume(with: result)
            }
            func restartIdle() {
                idleTask?.cancel()
                idleTask = Task { [weak self] in
                    guard let self else { return }
                    try? await Task.sleep(nanoseconds: self.idleTimeoutNanoseconds)
                    guard !Task.isCancelled else { return }
                    finish(.failure(DeviceError.incompleteDownload))
                }
            }

            // 不设置旧的完整 Data 回调，协议层不会累计长录音到内存。
            device.onDownloadComplete = nil
            device.onDownloadData = { [weak self] data in
                do {
                    try handle.write(contentsOf: data)
                    receivedThisAttempt += Int64(data.count)
                    self?.reportProgress(totalReceived: Int64(offset) + receivedThisAttempt)
                    restartIdle()
                } catch {
                    finish(.failure(error))
                }
            }
            device.onDownloadFinished = { [weak self] actualName in
                self?.statusText = "下载完成"
                self?.progress = 1
                self?.onProgress?(1, "下载完成")
                finish(.success(actualName))
            }
            device.onDownloadCode = { code in
                if code != 0 { finish(.failure(DeviceError.downloadCode(code))) }
            }
            device.requestImport(filename: name, offset: offset)
            restartIdle()
        }
    }

    private func reportProgress(totalReceived: Int64) {
        let value = expectedSize > 0 ? min(0.99, Double(totalReceived) / Double(expectedSize)) : 0
        progress = value
        statusText = totalReceived > 0 ? "下载中 \(totalReceived) 字节" : "正在等待设备数据…"
        onProgress?(value, statusText)
    }

    private func partialFileURL(file: CB08FileEntry, candidate: String) -> URL {
        let encodedName = candidate.utf8.map { String(format: "%02x", $0) }.joined()
        return storeDirectory
            .appendingPathComponent("downloads", isDirectory: true)
            .appendingPathComponent("\(file.time)-\(file.size)-\(encodedName).partial")
    }

    private func partialSize(at url: URL) -> Int64 {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
    }
}
