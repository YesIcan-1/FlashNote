import Foundation
import FlashNoteCore

enum DeviceError: Error, Equatable {
    case downloadCode(UInt8)
    case incompleteDownload
}

/// 设备文件 → 下载 WAV → 转写 → 保存 Transcript 的编排器。
@Observable
final class DeviceTranscriptionService {
    private let device: CB08Device
    private let engine: FileTranscriptionEngine
    private let store: RecordingStore
    private let storeDirectory: URL
    private let idleTimeoutNanoseconds: UInt64

    /// 进度 + 状态回调（供 ViewModel 刷新 UI）。
    var onProgress: ((Double, String) -> Void)?
    private(set) var progress: Double = 0
    private(set) var statusText = ""

    init(device: CB08Device, engine: FileTranscriptionEngine, store: RecordingStore, storeDirectory: URL = AppEnvironment.defaultStoreDirectory(), idleTimeoutNanoseconds: UInt64 = 6_000_000_000) {
        self.device = device
        self.engine = engine
        self.store = store
        self.storeDirectory = storeDirectory
        self.idleTimeoutNanoseconds = idleTimeoutNanoseconds
    }

    /// 下载设备文件并转写保存。
    func downloadAndTranscribe(file: CB08FileEntry, title: String) async throws -> Transcript {
        // 设备列表 size 是实际传输的压缩文件大小；用它作为下载进度分母，
        // WAV 只是后续解码产物，不能用于衡量 BLE 下载进度。
        expectedSize = max(1, file.size)
        progress = 0
        onProgress?(0, "开始下载…")
        
        let (audioData, actualName) = try await download(file: file)

        let id = UUID()
        let audioDir = storeDirectory.appendingPathComponent("audio", isDirectory: true)
        try FileManager.default.createDirectory(at: audioDir, withIntermediateDirectories: true)
        let dest = audioDir.appendingPathComponent("\(id.uuidString).wav")
        try audioData.write(to: dest)

        statusText = "转写中…"
        onProgress?(1, statusText)
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

    /// 异步下载（候选名回退：base.opus → base.wav → 原始名）。
    private func download(file: CB08FileEntry) async throws -> (Data, String) {
        let candidates = preferredDownloadCandidates(for: file)
        var lastError: Error = DeviceError.downloadCode(0)
        for (index, name) in candidates.enumerated() {
            do {
                progress = 0
                let (data, actualName) = try await downloadOne(name: name)
                if actualName.lowercased().hasSuffix(".opus") {
                    statusText = "正在解码为 WAV…"
                    onProgress?(1, statusText)
                    do {
                        return (try CB08OpusFileDecoder.decodeToWAV(data), actualName)
                    } catch {
                        // OPUS 损坏时保留可用性：继续尝试同名 WAV。
                        lastError = error
                        continue
                    }
                }
                return (data, actualName)
            } catch let error as DeviceError {
                lastError = error
                if error != .downloadCode(1) { throw error } // code=1 才换候选名
                _ = index
            }
        }
        throw lastError
    }

    /// 优先获取设备中的压缩 OPUS 文件；无法获取时再请求 WAV 和原始截断名。
    private func preferredDownloadCandidates(for file: CB08FileEntry) -> [String] {
        let candidates = file.candidateNames
        let opus = candidates.filter { $0.lowercased().hasSuffix(".opus") }
        let wav = candidates.filter { $0.lowercased().hasSuffix(".wav") }
        let raw = candidates.filter { name in
            !name.lowercased().hasSuffix(".opus") && !name.lowercased().hasSuffix(".wav")
        }
        return Array(NSOrderedSet(array: opus + wav + raw)) as? [String] ?? candidates
    }

    private var expectedSize: UInt32 = 0
    private func downloadOne(name: String) async throws -> (Data, String) {
        try await withCheckedThrowingContinuation { cont in
            var buffer = Data()
            var finished = false

            func resumeIfNeeded(_ result: Result<(Data, String), Error>) {
                guard !finished else { return }
                finished = true
                cont.resume(with: result)
            }

            // 空闲超时表示传输中断；只有设备结束帧才允许成功落盘。
            var idleTask: Task<Void, Never>?
            func restartIdle() {
                idleTask?.cancel()
                idleTask = Task {
                    try? await Task.sleep(nanoseconds: self.idleTimeoutNanoseconds)
                    guard !Task.isCancelled else { return }
                    resumeIfNeeded(.failure(buffer.isEmpty ? DeviceError.downloadCode(1) : DeviceError.incompleteDownload))
                }
            }

            device.onDownloadData = { [weak self] d in
                buffer.append(d)
                if let self {
                    let p = self.expectedSize > 0 ? min(1, Double(buffer.count) / Double(self.expectedSize)) : 0
                    self.progress = p
                    self.statusText = "下载中 \(buffer.count) 字节"
                    self.onProgress?(p, self.statusText)
                }
                restartIdle()
            }
            device.onDownloadComplete = { [weak self] data, actualName in
                idleTask?.cancel()
                self?.statusText = "下载完成"
                self?.progress = 1
                self?.onProgress?(1, self?.statusText ?? "下载完成")
                resumeIfNeeded(.success((data, actualName)))
            }
            device.onDownloadCode = { code in
                idleTask?.cancel()
                if code != 0 && !finished {
                    resumeIfNeeded(.failure(DeviceError.downloadCode(code)))
                }
            }
            device.requestImport(filename: name)
            restartIdle()
        }
    }
}
