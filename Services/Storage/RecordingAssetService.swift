import Foundation
import FlashNoteCore

/// 录音资料的本地文件边界：元数据由 Store 级联清理，音频资产由 App 层清理。
enum RecordingAssetService {
    static func audioURL(for recording: Recording, storeDirectory: URL = AppEnvironment.defaultStoreDirectory()) -> URL? {
        guard let filename = recording.audioFilename else { return nil }
        return storeDirectory.appendingPathComponent("audio", isDirectory: true).appendingPathComponent(filename)
    }

    static func delete(_ recording: Recording, from store: RecordingStore, storeDirectory: URL = AppEnvironment.defaultStoreDirectory()) throws {
        try store.deleteRecording(id: recording.id)
        if let audioURL = audioURL(for: recording, storeDirectory: storeDirectory),
           FileManager.default.fileExists(atPath: audioURL.path) {
            try FileManager.default.removeItem(at: audioURL)
        }
    }
}
