import Foundation
import Shared
import ClawLogging

// MARK: - HTTP Client

public struct HTTPClient: Sendable {
    public let baseURL: URL
    public let defaultHeaders: [String: String]
    private let session: URLSession

    public init(
        baseURL: URL,
        defaultHeaders: [String: String] = [:],
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.defaultHeaders = defaultHeaders
        self.session = session
    }

    // MARK: - JSON Request/Response

    public func request<T: Decodable>(
        path: String,
        method: HTTPMethod = .get,
        body: (any Encodable)? = nil,
        headers: [String: String] = [:]
    ) async throws -> T {
        let (data, response) = try await raw(path: path, method: method, body: body, headers: headers)
        guard let http = response as? HTTPURLResponse else {
            throw IRelayError.protocolError("Non-HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "<binary>"
            throw IRelayError.connectionFailed("HTTP \(http.statusCode): \(body)")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    // MARK: - Raw Request

    public func raw(
        path: String,
        method: HTTPMethod = .get,
        body: (any Encodable)? = nil,
        headers: [String: String] = [:]
    ) async throws -> (Data, URLResponse) {
        let url = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue

        for (key, value) in defaultHeaders { request.setValue(value, forHTTPHeaderField: key) }
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }

        if let body {
            request.httpBody = try JSONEncoder().encode(body)
            if request.value(forHTTPHeaderField: "Content-Type") == nil {
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }
        }

        return try await session.data(for: request)
    }
}

// MARK: - HTTP Method

public enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
}
