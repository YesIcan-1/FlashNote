import Testing
import Foundation
import FlashNoteCore
#if os(macOS)
@testable import FlashNoteMac
#else
@testable import FlashNote
#endif

struct AppEnvironmentTests {
    @Test func liveEnvironmentCreatesFileStore() throws {
        let env = AppEnvironment.makeLive()
        #expect(env.store is FileRecordingStore)
    }

    @Test func storeDirectoryUsesApplicationSupport() {
        let dir = AppEnvironment.defaultStoreDirectory()
        #expect(dir.lastPathComponent == "FlashNote")
        #expect(dir.path.contains("Application Support"))
    }

    @Test func storeRoundTripsRecording() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("EnvTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try FileRecordingStore(root: root)
        var rec = Recording(title: "测试")
        rec.markTranscribed()
        try store.upsertRecording(rec)
        #expect(try store.fetchRecording(id: rec.id) == rec)
    }
}
