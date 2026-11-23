import Testing
import Foundation
import Observation
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

    @Test func defaultEngineUsesLocalModel() {
        #expect(makeSettings().transcriptionEngine == .whisperKit)
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

    @Test func settingsChangesInvalidateObservers() {
        let settings = makeSettings()
        var changed = false
        withObservationTracking {
            _ = settings.llmAPIKey
            _ = settings.llmModel
        } onChange: {
            changed = true
        }
        settings.llmAPIKey = "test-key"
        #expect(changed)
    }

    @Test func selectingModelInvalidatesObserversImmediately() {
        let settings = makeSettings()
        var changed = false
        withObservationTracking {
            _ = settings.llmModel
        } onChange: { changed = true }
        settings.llmModel = "deepseek-v4-pro"
        #expect(changed)
        #expect(settings.llmModel == "deepseek-v4-pro")
    }

    @Test func providerPresetsAndKeysRemainIndependent() {
        let settings = makeSettings()
        #expect(settings.aiProvider == .deepSeek)
        #expect(settings.llmBaseURL == AIProvider.deepSeek.defaultBaseURL)
        #expect(settings.llmModel == AIProvider.deepSeek.defaultModel)
        settings.llmAPIKey = "deepseek-key"
        settings.aiProvider = .qwen
        #expect(settings.llmBaseURL == AIProvider.qwen.defaultBaseURL)
        #expect(settings.llmModel == AIProvider.qwen.defaultModel)
        settings.llmAPIKey = "qwen-key"
        settings.aiProvider = .deepSeek
        #expect(settings.llmAPIKey == "deepseek-key")
        settings.aiProvider = .qwen
        #expect(settings.llmAPIKey == "qwen-key")
    }

    @Test func modelCatalogUsesProviderEndpoint() throws {
        #expect(try ModelCatalog.modelsURL(baseURL: AIProvider.deepSeek.defaultBaseURL, provider: .deepSeek).absoluteString == "https://api.deepseek.com/models")
        #expect(try ModelCatalog.modelsURL(baseURL: AIProvider.qwen.defaultBaseURL, provider: .qwen).absoluteString == "https://dashscope.aliyuncs.com/api/v1/models")
    }
}
