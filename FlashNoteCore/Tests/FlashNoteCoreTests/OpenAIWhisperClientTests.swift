import Testing
import Foundation
@testable import FlashNoteCore

final class WhisperURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let handler = WhisperURLProtocol.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL)); return
        }
        do {
            let (resp, data) = try handler(request)
            client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

@Suite(.serialized)
struct OpenAIWhisperClientTests {
    private func session() -> URLSession {
        let c = URLSessionConfiguration.ephemeral
        c.protocolClasses = [WhisperURLProtocol.self]
        return URLSession(configuration: c)
    }

    @Test func transcribeParsesVerboseJsonSegments() async throws {
        let json = """
        {"text":"第一句。第二句。","segments":[
          {"id":0,"start":0.0,"end":1.5,"text":"第一句。","tokens":[]},
          {"id":1,"start":1.6,"end":3.0,"text":"第二句。","tokens":[]}
        ]}
        """
        WhisperURLProtocol.handler = { req in
            #expect(req.url?.path == "/v1/audio/transcriptions")
            #expect(req.httpMethod == "POST")
            #expect(req.value(forHTTPHeaderField: "Authorization") == "Bearer k")
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (resp, json.data(using: .utf8)!)
        }
        let client = OpenAIWhisperClient(
            baseURL: URL(string: "https://api.openai.com/v1")!,
            apiKey: "k", model: "whisper-1", session: session()
        )
        let segments = try await client.transcribe(audioData: Data([1, 2, 3]), filename: "a.m4a", language: "zh")
        #expect(segments.count == 2)
        #expect(segments[0].text == "第一句。")
        #expect(abs(segments[0].startTime - 0.0) < 0.001)
        #expect(abs(segments[1].endTime! - 3.0) < 0.001)
    }

    @Test func transcribeThrowsOnHTTPError() async {
        WhisperURLProtocol.handler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (resp, Data())
        }
        let client = OpenAIWhisperClient(baseURL: URL(string: "https://api.openai.com/v1")!, apiKey: "k", model: "whisper-1", session: session())
        await #expect(throws: LLMError.self) {
            _ = try await client.transcribe(audioData: Data(), filename: "a.m4a", language: "zh")
        }
    }

    @Test func malformedResponseThrowsInvalidResponse() async {
        WhisperURLProtocol.handler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (resp, "not json".data(using: .utf8)!)
        }
        let client = OpenAIWhisperClient(baseURL: URL(string: "https://api.openai.com/v1")!, apiKey: "k", model: "whisper-1", session: session())
        await #expect(throws: LLMError.self) {
            _ = try await client.transcribe(audioData: Data(), filename: "a.m4a", language: "zh")
        }
    }
}
