import Foundation

public enum LLMError: Error, Equatable {
    case httpStatus(Int)
    case invalidResponse
}

public protocol LLMClient: Sendable {
    var modelName: String { get }
    /// 非流式完成。
    func complete(messages: [ChatMessage]) async throws -> String
    /// 流式完成（SSE），逐段产出文本增量。
    func stream(messages: [ChatMessage]) -> AsyncThrowingStream<String, Error>
}

/// OpenAI 兼容 Chat Completions 客户端（DeepSeek / OpenAI / 通义 / Ollama 等均可通过 Base URL 接入）。
public final class OpenAICompatibleClient: LLMClient, @unchecked Sendable {
    public let modelName: String
    private let configuration: LLMConfiguration
    private let session: URLSession

    public init(configuration: LLMConfiguration, session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
        self.modelName = configuration.model
    }

    public func complete(messages: [ChatMessage]) async throws -> String {
        let request = try makeRequest(messages: messages, stream: false)
        let (data, response) = try await session.data(for: request)
        try Self.validate(response)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String,
              !content.isEmpty else {
            throw LLMError.invalidResponse
        }
        return content
    }

    public func stream(messages: [ChatMessage]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try self.makeRequest(messages: messages, stream: true)
                    let (bytes, response) = try await self.session.bytes(for: request)
                    try Self.validate(response)
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if payload == "[DONE]" { break }
                        guard let data = payload.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let choices = json["choices"] as? [[String: Any]],
                              let delta = choices.first?["delta"] as? [String: Any],
                              let content = delta["content"] as? String else { continue }
                        continuation.yield(content)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func makeRequest(messages: [ChatMessage], stream: Bool) throws -> URLRequest {
        let url = configuration.baseURL.appendingPathComponent("chat/completions")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        let body: [String: Any] = [
            "model": configuration.model,
            "messages": messages.map { ["role": $0.role.rawValue, "content": $0.content] },
            "temperature": configuration.temperature,
            "stream": stream
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private static func validate(_ response: URLResponse) throws {
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw LLMError.httpStatus(http.statusCode)
        }
    }
}
