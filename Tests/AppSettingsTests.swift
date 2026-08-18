import Testing
import Foundation
#if os(macOS)
@testable import FlashNoteMac
#else
@testable import FlashNote
#endif

final class MockKeychain: APIKeyStoring {
    var storage: [String: String] = [:]
    func get(_ key: String) -> String? { storage[key] }
    func set(_ value: String, for key: String) { storage[key] = value }
    func delete(_ key: String) { storage[key] = nil }
}

struct AppSettingsTests {
    private func makeSettings() -> AppSettings {
        AppSettings(storeDirectory: URL(fileURLWithPath: "/tmp"), keychain: MockKeychain(),
                    defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!)
    }

    @Test func defaultEngineIsCloud() {
        #expect(makeSettings().transcriptionEngine == .cloudWhisper)
    }

    @Test func engineRoundTrips() {
        let s = makeSettings()
        s.transcriptionEngine = .whisperKit
        #expect(s.transcriptionEngine == .whisperKit)
    }

    @Test func llmConfigPersists() {
        let s = makeSettings()
        s.llmBaseURL = "https://api.deepseek.com"
        s.llmModel = "deepseek-chat"
        s.llmAPIKey = "secret"
        #expect(s.llmBaseURL == "https://api.deepseek.com")
        #expect(s.llmModel == "deepseek-chat")
        #expect(s.llmAPIKey == "secret")
    }
}
