#if os(macOS)
import AppKit
import Foundation
import FlashNoteCore

/// macOS：监听外部卷挂载，识别录音卡（含 `record/` 目录的卷），
/// 按 `noteYYYYMMDD-HHMMSS.wav` 文件名增量导入本地媒体库，登记并自动转写。
///
/// - 去重：已导入的设备文件名持久化于 UserDefaults（键 `USBImportedFilenames`）。
/// - 转写：注入 `FileTranscriptionEngine`；转写失败不阻塞导入（保留 .recording 状态，详情页可重试）。
/// - 平台：仅 macOS（iOS 沙箱无法挂载外部卷，走文件 App 导入）。
@Observable
final class USBVolumeSyncEngine {
    enum State: Equatable {
        case idle
        case scanning
        case syncing(Int)
        case completed(Int, Int)   // imported, skipped
        case failed(String)
    }

    private(set) var state: State = .idle
    private(set) var lastSyncSummary: String?

    private let store: RecordingStore
    private let storeDirectory: URL
    private let transcriptionFactory: () -> FileTranscriptionEngine
    private let processing: RecordingProcessingCoordinator?
    private let importedFilenamesKey = "USBImportedFilenames"
    private var observers: [NSObjectProtocol] = []
    private var isSyncing = false

    init(
        store: RecordingStore,
        storeDirectory: URL = AppEnvironment.defaultStoreDirectory(),
        transcriptionFactory: @escaping () -> FileTranscriptionEngine,
        processing: RecordingProcessingCoordinator? = nil
    ) {
        self.store = store
        self.storeDirectory = storeDirectory
        self.transcriptionFactory = transcriptionFactory
        self.processing = processing
    }

    deinit { stopMonitoring() }

    // MARK: - Monitoring

    /// 开始监听卷挂载，并立即扫描当前已连接卷。可在 App 启动后调用（macOS）。
    func startMonitoring() {
        guard observers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.didMountNotification, object: nil, queue: .main) { [weak self] _ in
            Task { await self?.syncNow() }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didUnmountNotification, object: nil, queue: .main) { [weak self] _ in
            self?.lastSyncSummary = nil
        })
        Task { await syncNow() }
    }

    func stopMonitoring() {
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers = []
    }

    // MARK: - Sync

    /// 手动/挂载触发的全量同步：发现设备卷 → 扫描新录音 → 增量导入。
    func syncNow() async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        state = .scanning
        guard let volume = findDeviceVolume() else {
            state = .idle
            lastSyncSummary = "未检测到录音卡（插上 USB 后会自动同步）"
            return
        }

        let files = scanRecordings(on: volume)
        guard !files.isEmpty else {
            state = .idle
            lastSyncSummary = "录音卡已连接，未发现新录音"
            return
        }

        var imported = 0
        var skipped = 0
        state = .syncing(files.count)
        for file in files {
            if alreadyImported(file.name) {
                skipped += 1
                continue
            }
            do {
                try await importFile(file, from: volume)
                markImported(file.name)
                imported += 1
            } catch {
                lastSyncSummary = "导入 \(file.name) 失败：\(error.localizedDescription)"
                processing?.downloadFailed(title: file.name, error: error)
            }
        }
        state = .completed(imported, skipped)
        lastSyncSummary = imported > 0
            ? "已导入 \(imported) 条新录音，跳过 \(skipped) 条"
            : "无新录音（跳过 \(skipped) 条）"
    }

    // MARK: - Discovery

    private func findDeviceVolume() -> URL? {
        let fm = FileManager.default
        let volumes = fm.mountedVolumeURLs(includingResourceValuesForKeys: nil, options: .skipHiddenVolumes) ?? []
        return volumes.first { url in
            guard url.path != "/" else { return false }
            let recordDir = url.appendingPathComponent("record", isDirectory: true)
            var isDirectory: ObjCBool = false
            return fm.fileExists(atPath: recordDir.path, isDirectory: &isDirectory) && isDirectory.boolValue
        }
    }

    private struct DeviceAudioFile {
        let name: String          // note20260910-161330.wav
        let url: URL
        let recordedAt: Date
    }

    private func scanRecordings(on volume: URL) -> [DeviceAudioFile] {
        let recordDir = volume.appendingPathComponent("record", isDirectory: true)
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: recordDir,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        // 只取 WAV（与 .opus 成对存在，优先 WAV 直接转写，无需解码）。
        let wavs = entries.filter { $0.lastPathComponent.hasPrefix("note") && $0.lastPathComponent.hasSuffix(".wav") }
        return wavs.sorted { $0.lastPathComponent < $1.lastPathComponent }.map { url in
            let name = url.lastPathComponent
            return DeviceAudioFile(name: name, url: url, recordedAt: Self.parseDate(from: name) ?? .distantPast)
        }
    }

    /// `noteYYYYMMDD-HHMMSS.wav` → Date
    private static func parseDate(from name: String) -> Date? {
        guard name.hasPrefix("note") else { return nil }
        let core = String(name.dropFirst(4).replacingOccurrences(of: ".wav", with: ""))
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        formatter.timeZone = .current
        return formatter.date(from: core)
    }

    // MARK: - Import

    private func importFile(_ file: DeviceAudioFile, from volume: URL) async throws {
        let fm = FileManager.default
        let id = UUID()
        let audioDir = storeDirectory.appendingPathComponent("audio", isDirectory: true)
        try fm.createDirectory(at: audioDir, withIntermediateDirectories: true)
        let destination = audioDir.appendingPathComponent("\(id.uuidString).wav")
        processing?.downloadStarted(title: file.name)

        // 经统一传输通道复制（流式 + 进度），避免大文件一次性驻留内存。
        _ = try await USBVolumeTransferChannel().transfer(
            sourceURL: file.url,
            to: destination,
            onProgress: { _, _ in }
        )

        var recording = Recording(
            id: id,
            title: file.name.replacingOccurrences(of: ".wav", with: ""),
            audioFilename: destination.lastPathComponent
        )
        recording.createdAt = file.recordedAt
        recording.updatedAt = file.recordedAt
        recording.duration = Self.duration(ofWAV: destination)
        try store.upsertRecording(recording)
        processing?.downloadCompleted(title: file.name)
        processing?.beginTranscription(id)

        // 自动转写：失败不阻塞登记（保持 .recording，详情页可重试）。
        let engine = transcriptionFactory()
        guard engine.isAvailable else {
            processing?.transcriptionFailed(id, error: TranscriptionError.engineUnavailable)
            return
        }
        do {
            _ = try await RecordingTranscriptionService(store: store, engine: engine, storeDirectory: storeDirectory)
                .transcribe(recording)
            processing?.transcriptionCompleted(id)
            Task { await processing?.generateAll(recordingID: id) }
        } catch {
            processing?.transcriptionFailed(id, error: error)
            lastSyncSummary = "已导入但转写失败（可在详情页重试）：\(file.name)"
        }
    }

    /// WAV 时长估算：data 区字节数 / 字节率（设备固定 16kHz/16bit/单声道 = 32000 B/s）。
    private static func duration(ofWAV url: URL) -> TimeInterval {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return 0 }
        defer { try? handle.close() }
        guard let header = try? handle.read(upToCount: 44), header.count == 44 else { return 0 }
        guard header[0] == 0x52, header[1] == 0x49 else { return 0 } // "RI"
        // byteRate @ 28 (LE)，dataSize @ 40 (LE)
        let byteRate = Self.leUInt32(header, offset: 28)
        let dataSize = Self.leUInt32(header, offset: 40)
        guard byteRate > 0 else { return 0 }
        return TimeInterval(dataSize) / TimeInterval(byteRate)
    }

    private static func leUInt32(_ bytes: Data, offset: Int) -> UInt32 {
        bytes.withUnsafeBytes { raw in
            let p = raw.baseAddress!.advanced(by: offset).assumingMemoryBound(to: UInt32.self)
            return UInt32(littleEndian: p.pointee)
        }
    }

    // MARK: - Dedup

    private var importedFilenames: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: importedFilenamesKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: importedFilenamesKey) }
    }

    private func alreadyImported(_ name: String) -> Bool { importedFilenames.contains(name) }

    private func markImported(_ name: String) {
        var set = importedFilenames
        set.insert(name)
        importedFilenames = set
    }
}
#endif
