import Foundation
import ProviderKit
import Shared
import Networking
import IRelayLogging

// MARK: - Ollama Provider

/// Ollama local LLM provider — uses the OpenAI-compatible API.
public struct OllamaProvider: LLMProvider, Sendable {
    public let id = "ollama"
    public let displayName = "Ollama (Local)"

    private let client: HTTPClient
    private let logger = Log.providers

    public init(baseURL: URL? = nil) {
        self.client = HTTPClient(
            baseURL: baseURL ?? URL(string: "http://localhost:11434")!,
            defaultHeaders: ["Content-Type": "application/json"]
        )
    }

    public var supportedModels: [ModelInfo] {
        // Ollama models are dynamic — these are common defaults
        [
            ModelInfo(id: "llama3.3", displayName: "Llama 3.3 70B", contextWindow: 128_000, supportsTools: false),
            ModelInfo(id: "mistral", displayName: "Mistral 7B", contextWindow: 32_000, supportsTools: false),
            ModelInfo(id: "codellama", displayName: "Code Llama", contextWindow: 16_000, supportsTools: false),
        ]
    }

    public func validate() async throws -> Bool {
        let (_, response) = try await client.raw(path: "/api/tags")
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            return false
        }
        return true
    }

    public func complete(
        _ messages: [ChatMessage],
        model: String,
        options: CompletionOptions
    ) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let apiMessages = messages.map { msg in
                        OllamaMessage(role: msg.role.rawValue, content: msg.textContent)
                    }

                    let body = OllamaChatRequest(
                        model: model,
                        messages: apiMessages,
                        stream: true,
                        options: OllamaOptions(
                            num_predict: options.maxTokens,
                            temperature: options.temperature
                        )
                    )

                    let bodyData = try JSONEncoder().encode(body)
                    let url = client.baseURL.appendingPathComponent("/api/chat")

                    // Ollama uses newline-delimited JSON, not SSE
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.httpBody = bodyData
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    guard let http = response as? HTTPURLResponse,
                          (200..<300).contains(http.statusCode) else {
                        throw IRelayError.streamingFailed("Ollama HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
                    }

                    for try await line in bytes.lines {
                        guard let data = line.data(using: .utf8),
                              let chunk = try? JSONDecoder().decode(OllamaChatResponse.self, from: data) else {
                            continue
                        }

                        if let content = chunk.message?.content, !content.isEmpty {
                            continuation.yield(.text(content))
                        }
                        if chunk.done {
                            continuation.yield(.done(.endTurn))
                        }
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

// MARK: - API Types

private struct OllamaChatRequest: Encodable {
    let model: String
    let messages: [OllamaMessage]
    let stream: Bool
    let options: OllamaOptions?
}

private struct OllamaMessage: Codable {
    let role: String
    let content: String
}

private struct OllamaOptions: Encodable {
    let num_predict: Int?
    let temperature: Double?
}

private struct OllamaChatResponse: Decodable {
    let message: OllamaMessage?
    let done: Bool
}
