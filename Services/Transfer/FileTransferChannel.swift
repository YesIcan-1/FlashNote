import Foundation

/// 统一文件传输通道：把来源音频传输到本地目标 URL。
///
/// 实现：
/// - `USBVolumeTransferChannel`：USB 卷 → 本地，流式复制（约 30MB/s，带进度）；
/// - BLE 设备文件：由 `DeviceTranscriptionService` 编排（断点续传 / 候选名回退 / OPUS 解码 / 转写），
///   属于会话式通道，未来 `SyncEngine` 统一调度时经适配器接入，本层不重复实现。
protocol FileTransferChannel: AnyObject {
    var displayName: String { get }
    /// 将 sourceURL 传输到 destination，onProgress(0...1, 阶段文案)。
    /// 返回实际落盘文件名（destination 的 lastPathComponent）。
    func transfer(
        sourceURL: URL,
        to destination: URL,
        onProgress: @escaping (Double, String) -> Void
    ) async throws -> String
}

/// USB 卷直读通道：流式分块复制并回报进度。
final class USBVolumeTransferChannel: FileTransferChannel {
    var displayName: String { "USB 直读" }

    private let chunkSize = 1 << 20 // 1MB

    func transfer(
        sourceURL: URL,
        to destination: URL,
        onProgress: @escaping (Double, String) -> Void
    ) async throws -> String {
        let fm = FileManager.default
        let input = try FileHandle(forReadingFrom: sourceURL)
        defer { try? input.close() }
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
        guard fm.createFile(atPath: destination.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }

        let output = try FileHandle(forWritingTo: destination)
        defer { try? output.close() }

        let total = (try? sourceURL.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Double.init) ?? 0
        var written: Double = 0
        onProgress(0, "正在复制…")
        while let chunk = try input.read(upToCount: chunkSize), !chunk.isEmpty {
            try output.write(contentsOf: chunk)
            written += Double(chunk.count)
            if total > 0 {
                onProgress(min(0.99, written / total), "正在复制… \(Self.bytes(written)) / \(Self.bytes(total))")
            }
            if Task.isCancelled {
                try? fm.removeItem(at: destination)
                throw CancellationError()
            }
        }
        onProgress(1, "复制完成")
        return destination.lastPathComponent
    }

    private static func bytes(_ value: Double) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .file)
    }
}
