import Testing
import Foundation
import FlashNoteCore
#if os(macOS)
@testable import FlashNoteMac
#else
@testable import FlashNote
#endif

struct CloudWhisperEngineTests {
    private func settings(key: String?) -> AppSettings {
        let s = AppSettings(storeDirectory: URL(fileURLWithPath: "/tmp"), keychain: MockKeychain(),
                            defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!)
        if let key { s.llmAPIKey = key }
        return s
    }

    @Test func engineIsAvailableWhenKeyPresent() {
        #expect(CloudWhisperEngine(settings: settings(key: "k")).isAvailable)
    }

    @Test func engineUnavailableWithoutKey() {
        #expect(!CloudWhisperEngine(settings: settings(key: nil)).isAvailable)
    }
}
