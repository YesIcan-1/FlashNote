import Foundation
import FlashNoteCore
import os
import AVFoundation

enum DeviceError: Error, Equatable {
    case downloadCode(UInt8)
    case incompleteDownload
}

extension DeviceError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .downloadCode(let code): "设备返回下载错误码 \(code)"
        case .incompleteDownload: "下载中断，重新点击可从断点继续"
        }
    }
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
    var onRecordingCreated: ((UUID) -> Void)?
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
        progress = 0
        onProgress?(0, "准备下载…")

        let (downloadedURL, actualName) = try await download(file: file)
        let id = UUID()
        let audioDir = storeDirectory.appendingPathComponent("audio", isDirectory: true)
        try FileManager.default.createDirectory(at: audioDir, withIntermediateDirectories: true)
        let destination = audioDir.appendingPathComponent("\(id.uuidString).wav")
        if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
        try FileManager.default.moveItem(at: downloadedURL, to: destination)

        let resolvedTitle = title.isEmpty
            ? URL(fileURLWithPath: actualName).deletingPathExtension().lastPathComponent
            : title
        var recording = Recording(id: id, title: resolvedTitle)
        recording.audioFilename = destination.lastPathComponent
        recording.sourceDeviceName = file.displayName
        if let audio = try? AVAudioFile(forReading: destination), audio.processingFormat.sampleRate > 0 {
            recording.duration = Double(audio.length) / audio.processingFormat.sampleRate
        }
        try store.upsertRecording(recording)
        onRecordingCreated?(id)

        statusText = "转写中…"
        onProgress?(1, statusText)
        guard engine.isAvailable else { throw TranscriptionError.engineUnavailable }
        let segments = try await engine.transcribe(audioFileURL: destination, language: "zh")
        let transcript = Transcript(recordingID: id, segments: segments, language: "zh")

        try store.upsertTranscript(transcript)
        recording.markTranscribed()
        try store.upsertRecording(recording)
        statusText = "完成"
        return transcript
    }

    private func download(file: CB08FileEntry) async throws -> (URL, String) {
        var lastError: Error = DeviceError.downloadCode(0)
        for name in preferredDownloadCandidates(for: file) {
            let partialURL = partialFileURL(file: file, candidate: name)
            do {
                // 列表 size 是设备内 OPUS 体积，WAV 回退时不能拿它计算百分比。
                expectedSize = name.lowercased().hasSuffix(".opus") ? file.size : 0
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

    /// BLE 通道下载候选顺序：**OPUS 优先**（实机 4.2MB vs WAV 67.7MB，差 16 倍，
    /// BLE 带宽受限，小 16 倍即快 16 倍；下载后本地解码为 WAV 再转写）。
    /// 回退顺序：.opus → .wav → 原始截断名；仅在设备明确报不存在（code=1 且 0 字节）时切换。
    private func preferredDownloadCandidates(for file: CB08FileEntry) -> [String] {
        let candidates = file.candidateNames
        let opus = candidates.filter { $0.lowercased().hasSuffix(".opus") }
        let wav = candidates.filter { $0.lowercased().hasSuffix(".wav") }
        let raw = candidates.filter { !$0.lowercased().hasSuffix(".opus") && !$0.lowercased().hasSuffix(".wav") }
        return Array(NSOrderedSet(array: opus + wav + raw)) as? [String] ?? candidates
    }

    private var expectedSize: UInt32 = 0
    private var lastReportedProgress: Double = -1
    private var lastReportedBytes: Int64 = -1
    private func downloadOne(name: String, partialURL: URL) async throws -> String {
        let manager = FileManager.default
        try manager.createDirectory(at: partialURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !manager.fileExists(atPath: partialURL.path) { manager.createFile(atPath: partialURL.path, contents: nil) }
        let offset = UInt32(min(partialSize(at: partialURL), Int64(UInt32.max)))
        let handle = try FileHandle(forWritingTo: partialURL)
        try handle.seekToEnd()
        var receivedThisAttempt: Int64 = 0
        var packetCount = 0
        var callbackNanoseconds: UInt64 = 0
        var lastPacketNanoseconds: UInt64?
        var maxGapNanoseconds: UInt64 = 0
        var gapsOver20ms = 0
        var gapBuckets = [Int](repeating: 0, count: 7)
        let gapLimits: [UInt64] = [1_000_000, 5_000_000, 10_000_000, 20_000_000, 40_000_000, 80_000_000]
        var smallestPacket = Int.max
        var largestPacket = 0
        let startedAt = Date()
        lastReportedProgress = -1
        lastReportedBytes = -1
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
                let callbackStart = DispatchTime.now().uptimeNanoseconds
                defer { callbackNanoseconds += DispatchTime.now().uptimeNanoseconds - callbackStart }
                if let previous = lastPacketNanoseconds {
                    let gap = callbackStart - previous
                    maxGapNanoseconds = max(maxGapNanoseconds, gap)
                    if gap > 20_000_000 { gapsOver20ms += 1 }
                    let bucket = gapLimits.firstIndex(where: { gap < $0 }) ?? 6
                    gapBuckets[bucket] += 1
                }
                lastPacketNanoseconds = callbackStart
                packetCount += 1
                smallestPacket = min(smallestPacket, data.count)
                largestPacket = max(largestPacket, data.count)
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
                let elapsed = Date().timeIntervalSince(startedAt)
                let callbackMilliseconds = Double(callbackNanoseconds) / 1_000_000
                let maxGapMilliseconds = Double(maxGapNanoseconds) / 1_000_000
                deviceLogger.info("BLE download bytes=\(receivedThisAttempt, privacy: .public) packets=\(packetCount, privacy: .public) elapsed=\(elapsed, privacy: .public)s callback=\(callbackMilliseconds, privacy: .public)ms maxGap=\(maxGapMilliseconds, privacy: .public)ms gapsOver20ms=\(gapsOver20ms, privacy: .public)")
                deviceLogger.info("BLE packet sizes min=\(smallestPacket, privacy: .public) max=\(largestPacket, privacy: .public); gaps <1/<5/<10/<20/<40/<80/>=80ms: \(String(describing: gapBuckets), privacy: .public)")
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
        let shouldReport = expectedSize > 0
            ? lastReportedProgress < 0 || value - lastReportedProgress >= 0.01
            : lastReportedBytes < 0 || totalReceived - lastReportedBytes >= 65_536
        guard shouldReport else { return }
        lastReportedProgress = value
        lastReportedBytes = totalReceived
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
