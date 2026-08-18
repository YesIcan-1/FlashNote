import Foundation

/// 整段音频转写客户端抽象（导入音频用）。
public protocol AudioTranscriptionClient: Sendable {
    /// 上传音频并返回分句段落（带起止时间戳）。
    func transcribe(audioData: Data, filename: String, language: String) async throws -> [TranscriptSegment]
}

/// OpenAI 兼容 `/audio/transcriptions` 客户端（Whisper API）。
public final class OpenAIWhisperClient: AudioTranscriptionClient, @unchecked Sendable {
    private let baseURL: URL
    private let apiKey: String
    private let model: String
    private let session: URLSession

    public init(baseURL: URL, apiKey: String, model: String = "whisper-1", session: URLSession = .shared) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.model = model
        self.session = session
    }

    public func transcribe(audioData: Data, filename: String, language: String) async throws -> [TranscriptSegment] {
        let url = baseURL.appendingPathComponent("audio/transcriptions")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let boundary = "FlashNote-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        var body = Data()
        func append(_ string: String) { body.append(string.data(using: .utf8)!) }
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"model\"\r\n\r\n\(model)\r\n")
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"language\"\r\n\r\n\(language)\r\n")
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"response_format\"\r\n\r\nverbose_json\r\n")
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n")
        append("Content-Type: application/octet-stream\r\n\r\n")
        body.append(audioData)
        append("\r\n--\(boundary)--\r\n")
        request.httpBody = body

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw LLMError.httpStatus(http.statusCode)
        }
        return try Self.parseVerboseJSON(data)
    }

    static func parseVerboseJSON(_ data: Data) throws -> [TranscriptSegment] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let segments = json["segments"] as? [[String: Any]] else {
            throw LLMError.invalidResponse
        }
        return segments.compactMap { dict in
            guard let text = dict["text"] as? String, !text.isEmpty else { return nil }
            let start = (dict["start"] as? NSNumber)?.doubleValue ?? 0
            let end = (dict["end"] as? NSNumber)?.doubleValue
            return TranscriptSegment(
                startTime: start,
                endTime: end,
                text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                isFinal: true
            )
        }
    }
}
