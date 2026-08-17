import Foundation

/// Chat 消息。
public struct ChatMessage: Codable, Equatable, Sendable {
    public enum Role: String, Codable, Sendable {
        case system, user, assistant
    }

    public var role: Role
    public var content: String

    public init(role: Role, content: String) {
        self.role = role
        self.content = content
    }
}

/// OpenAI 兼容服务的连接配置（用户可在设置中修改；apiKey 由 App 层存 Keychain）。
public struct LLMConfiguration: Codable, Equatable, Sendable {
    public var baseURL: URL
    public var apiKey: String
    public var model: String
    public var temperature: Double

    public init(
        baseURL: URL = URL(string: "https://api.deepseek.com")!,
        apiKey: String,
        model: String = "deepseek-chat",
        temperature: Double = 0.3
    ) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.model = model
        self.temperature = temperature
    }
}
