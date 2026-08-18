import Foundation
import Security

/// 转写引擎选择。
enum TranscriptionEngineChoice: String, CaseIterable, Identifiable {
    case cloudWhisper
    case whisperKit
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .cloudWhisper: "云端 Whisper API"
        case .whisperKit: "本地 WhisperKit"
        }
    }
}

/// API Key 存储抽象（Keychain 实现 / 测试内存实现）。
protocol APIKeyStoring {
    func get(_ key: String) -> String?
    func set(_ value: String, for key: String)
    func delete(_ key: String)
}

/// Keychain 实现。
final class KeychainAPIKeyStore: APIKeyStoring {
    func get(_ key: String) -> String? {
        var query = Self.query(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    func set(_ value: String, for key: String) {
        let data = Data(value.utf8)
        var query = Self.query(for: key)
        let update = [kSecValueData as String: data]
        if SecItemUpdate(query as CFDictionary, update as CFDictionary) != errSecSuccess {
            query[kSecValueData as String] = data
            SecItemAdd(query as CFDictionary, nil)
        }
    }
    func delete(_ key: String) {
        SecItemDelete(Self.query(for: key) as CFDictionary)
    }
    private static func query(for key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.flashnote.app",
         kSecAttrAccount as String: key]
    }
}

/// 应用设置：转写引擎偏好 + LLM 连接（apiKey 存 Keychain）。
@Observable
final class AppSettings {
    private let keychain: APIKeyStoring
    private let defaults: UserDefaults

    var transcriptionEngine: TranscriptionEngineChoice {
        get { TranscriptionEngineChoice(rawValue: defaults.string(forKey: "transcriptionEngine") ?? "") ?? .cloudWhisper }
        set { defaults.set(newValue.rawValue, forKey: "transcriptionEngine") }
    }

    var llmBaseURL: String {
        get { defaults.string(forKey: "llmBaseURL") ?? "https://api.deepseek.com" }
        set { defaults.set(newValue, forKey: "llmBaseURL") }
    }

    var llmModel: String {
        get { defaults.string(forKey: "llmModel") ?? "deepseek-chat" }
        set { defaults.set(newValue, forKey: "llmModel") }
    }

    var llmAPIKey: String {
        get { keychain.get("llmAPIKey") ?? "" }
        set { keychain.set(newValue, for: "llmAPIKey") }
    }

    init(storeDirectory: URL, keychain: APIKeyStoring = KeychainAPIKeyStore(), defaults: UserDefaults = .standard) {
        self.keychain = keychain
        self.defaults = defaults
    }
}
