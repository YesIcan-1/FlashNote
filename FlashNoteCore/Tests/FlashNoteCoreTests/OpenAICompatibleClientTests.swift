import Foundation
import Testing
@testable import FlashNoteCore

/// URLProtocol 桩：捕获请求并返回预设响应。
final class MockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = MockURLProtocol.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

// .serialized：MockURLProtocol.requestHandler 是共享静态状态，
// 串行执行防止测试并行互相覆盖。
@Suite(.serialized)
struct OpenAICompatibleClientTests {
    private func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    private func makeConfig() -> LLMConfiguration {
        LLMConfiguration(
            baseURL: URL(string: "https://api.deepseek.com")!,
            apiKey: "test-key",
            model: "deepseek-chat",
            temperature: 0.3
        )
    }

    /// URLSession 在交给 URLProtocol 前会把 httpBody 转为 httpBodyStream，
    /// 因此从两者中取请求体。
    private func body(of request: URLRequest) -> Data {
        if let httpBody = request.httpBody { return httpBody }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }

    @Test func completeParsesContent() async throws {
        let json = """
        {"choices":[{"message":{"role":"assistant","content":"会议结论：通过。"}}]}
        """
        MockURLProtocol.requestHandler = { request in
            #expect(request.url?.path == "/chat/completions")
            #expect(request.httpMethod == "POST")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-key")
            let body = body(of: request)
            let obj = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            #expect(obj?["model"] as? String == "deepseek-chat")
            #expect(obj?["stream"] as? Bool == false)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, json.data(using: .utf8)!)
        }
        let client = OpenAICompatibleClient(configuration: makeConfig(), session: makeSession())
        let result = try await client.complete(messages: [ChatMessage(role: .user, content: "hi")])
        #expect(result == "会议结论：通过。")
        #expect(client.modelName == "deepseek-chat")
    }

    @Test func completeThrowsOnHTTPError() async {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }
        let client = OpenAICompatibleClient(configuration: makeConfig(), session: makeSession())
        do {
            _ = try await client.complete(messages: [])
            Issue.record("应当抛出错误")
        } catch let error as LLMError {
            #expect(error == .httpStatus(401))
        } catch {
            Issue.record("错误的错误类型: \(error)")
        }
    }

    @Test func streamParsesSSE() async throws {
        let sse = """
        data: {"choices":[{"delta":{"content":"你"}}]}

        data: {"choices":[{"delta":{"content":"好"}}]}

        data: [DONE]

        """
        MockURLProtocol.requestHandler = { request in
            let obj = try JSONSerialization.jsonObject(with: body(of: request)) as? [String: Any]
            #expect(obj?["stream"] as? Bool == true)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, sse.data(using: .utf8)!)
        }
        let client = OpenAICompatibleClient(configuration: makeConfig(), session: makeSession())
        var collected = ""
        for try await piece in client.stream(messages: []) {
            collected += piece
        }
        #expect(collected == "你好")
    }

    @Test func streamThrowsOnHTTPError() async {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 429, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }
        let client = OpenAICompatibleClient(configuration: makeConfig(), session: makeSession())
        do {
            for try await _ in client.stream(messages: []) {}
            Issue.record("应当抛出错误")
        } catch let error as LLMError {
            #expect(error == .httpStatus(429))
        } catch {
            Issue.record("错误的错误类型: \(error)")
        }
    }
}
