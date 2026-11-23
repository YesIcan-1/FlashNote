import Foundation

enum ModelCatalogError: LocalizedError {
    case invalidBaseURL
    case httpStatus(Int)
    case invalidResponse
    var errorDescription: String? {
        switch self {
        case .invalidBaseURL: "API 地址无效"
        case .httpStatus(let code): "获取模型失败（HTTP \(code)）"
        case .invalidResponse: "服务未返回兼容的模型列表"
        }
    }
}

enum ModelCatalog {
    static func modelsURL(baseURL: String, provider: AIProvider) throws -> URL {
        guard let base = URL(string: baseURL), let scheme = base.scheme, let host = base.host,
              !scheme.isEmpty, !host.isEmpty else { throw ModelCatalogError.invalidBaseURL }
        if provider == .qwen && host.hasSuffix("aliyuncs.com") {
            var components = URLComponents(url: base, resolvingAgainstBaseURL: false)!
            components.path = "/api/v1/models"
            components.query = nil
            guard let url = components.url else { throw ModelCatalogError.invalidBaseURL }
            return url
        }
        return base.appendingPathComponent("models")
    }

    static func fetch(baseURL: String, apiKey: String, provider: AIProvider = .deepSeek) async throws -> [String] {
        let url = try modelsURL(baseURL: baseURL, provider: provider)
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ModelCatalogError.httpStatus((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entries = json["data"] as? [[String: Any]] else { throw ModelCatalogError.invalidResponse }
        return entries.compactMap { $0["id"] as? String }.sorted()
    }
}
