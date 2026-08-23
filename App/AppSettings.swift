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

/// 应用设置：转写引擎偏好 + LLM 连接。
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
        // 用户要求设置页不触发系统钥匙串授权；密钥仅保存在当前 Mac 的应用偏好中。
        get { defaults.string(forKey: "llmAPIKey") ?? "" }
        set { defaults.set(newValue, forKey: "llmAPIKey") }
    }

    /// 百炼 Qwen3-ASR 与 DeepSeek 纪要完全独立的配置。
    var qwenASRAPIKey: String {
        get { defaults.string(forKey: "qwenASRAPIKey") ?? "" }
        set { defaults.set(newValue, forKey: "qwenASRAPIKey") }
    }
    var qwenASRWorkspaceID: String {
        get { defaults.string(forKey: "qwenASRWorkspaceID") ?? "" }
        set { defaults.set(newValue, forKey: "qwenASRWorkspaceID") }
    }
    var qwenASRFileModel: String {
        get { defaults.string(forKey: "qwenASRFileModel") ?? "qwen3-asr-flash-filetrans" }
        set { defaults.set(newValue, forKey: "qwenASRFileModel") }
    }
    var qwenASRRealtimeModel: String {
        get { defaults.string(forKey: "qwenASRRealtimeModel") ?? "qwen3-asr-realtime" }
        set { defaults.set(newValue, forKey: "qwenASRRealtimeModel") }
    }

    init(storeDirectory: URL, keychain: APIKeyStoring = KeychainAPIKeyStore(), defaults: UserDefaults = .standard) {
        self.keychain = keychain
        self.defaults = defaults
    }
}
