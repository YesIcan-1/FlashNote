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

enum AIProvider: String, CaseIterable, Identifiable {
    case deepSeek
    case qwen

    var id: String { rawValue }
    var displayName: String { self == .deepSeek ? "DeepSeek" : "千问 Qwen" }
    var defaultBaseURL: String {
        self == .deepSeek ? "https://api.deepseek.com" : "https://dashscope.aliyuncs.com/compatible-mode/v1"
    }
    var defaultModel: String { self == .deepSeek ? "deepseek-flash" : "qwen-plus" }
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
    @ObservationIgnored
    private let keychain: APIKeyStoring
    @ObservationIgnored
    private let defaults: UserDefaults

    var transcriptionEngine: TranscriptionEngineChoice { didSet { defaults.set(transcriptionEngine.rawValue, forKey: "transcriptionEngine") } }
    var aiProvider: AIProvider { didSet { defaults.set(aiProvider.rawValue, forKey: "aiProvider") } }
    var deepSeekBaseURL: String { didSet { defaults.set(deepSeekBaseURL, forKey: "deepSeekBaseURL") } }
    var deepSeekModel: String { didSet { defaults.set(deepSeekModel, forKey: "deepSeekModel") } }
    var deepSeekAPIKey: String { didSet { defaults.set(deepSeekAPIKey, forKey: "deepSeekAPIKey") } }
    var qwenBaseURL: String { didSet { defaults.set(qwenBaseURL, forKey: "qwenBaseURL") } }
    var qwenModel: String { didSet { defaults.set(qwenModel, forKey: "qwenModel") } }
    var qwenAPIKey: String { didSet { defaults.set(qwenAPIKey, forKey: "qwenAPIKey") } }
    var qwenASRWorkspaceID: String { didSet { defaults.set(qwenASRWorkspaceID, forKey: "qwenASRWorkspaceID") } }
    var qwenASRFileModel: String { didSet { defaults.set(qwenASRFileModel, forKey: "qwenASRFileModel") } }
    var qwenASRRealtimeModel: String { didSet { defaults.set(qwenASRRealtimeModel, forKey: "qwenASRRealtimeModel") } }

    var llmBaseURL: String {
        get { aiProvider == .deepSeek ? deepSeekBaseURL : qwenBaseURL }
        set { if aiProvider == .deepSeek { deepSeekBaseURL = newValue } else { qwenBaseURL = newValue } }
    }
    var llmModel: String {
        get { aiProvider == .deepSeek ? deepSeekModel : qwenModel }
        set { if aiProvider == .deepSeek { deepSeekModel = newValue } else { qwenModel = newValue } }
    }
    var llmAPIKey: String {
        get { aiProvider == .deepSeek ? deepSeekAPIKey : qwenAPIKey }
        set { if aiProvider == .deepSeek { deepSeekAPIKey = newValue } else { qwenAPIKey = newValue } }
    }
    var qwenASRAPIKey: String {
        get { qwenAPIKey }
        set { qwenAPIKey = newValue }
    }

    init(storeDirectory: URL, keychain: APIKeyStoring = KeychainAPIKeyStore(), defaults: UserDefaults = .standard) {
        self.keychain = keychain
        self.defaults = defaults
        transcriptionEngine = TranscriptionEngineChoice(rawValue: defaults.string(forKey: "transcriptionEngine") ?? "") ?? .whisperKit
        aiProvider = AIProvider(rawValue: defaults.string(forKey: "aiProvider") ?? "") ?? .deepSeek
        deepSeekBaseURL = defaults.string(forKey: "deepSeekBaseURL") ?? defaults.string(forKey: "llmBaseURL") ?? AIProvider.deepSeek.defaultBaseURL
        deepSeekModel = defaults.string(forKey: "deepSeekModel") ?? defaults.string(forKey: "llmModel") ?? AIProvider.deepSeek.defaultModel
        deepSeekAPIKey = defaults.string(forKey: "deepSeekAPIKey") ?? defaults.string(forKey: "llmAPIKey") ?? ""
        qwenBaseURL = defaults.string(forKey: "qwenBaseURL") ?? AIProvider.qwen.defaultBaseURL
        qwenModel = defaults.string(forKey: "qwenModel") ?? AIProvider.qwen.defaultModel
        qwenAPIKey = defaults.string(forKey: "qwenAPIKey") ?? defaults.string(forKey: "qwenASRAPIKey") ?? ""
        qwenASRWorkspaceID = defaults.string(forKey: "qwenASRWorkspaceID") ?? ""
        qwenASRFileModel = defaults.string(forKey: "qwenASRFileModel") ?? "qwen3-asr-flash-filetrans"
        qwenASRRealtimeModel = defaults.string(forKey: "qwenASRRealtimeModel") ?? "qwen3-asr-realtime"
    }
}
