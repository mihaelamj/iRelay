import Foundation
import ProviderKit
import Shared
import Networking
import ClawLogging

// MARK: - OpenAI Provider

public struct OpenAIProvider: LLMProvider, Sendable {
    public let id = "openai"
    public let displayName = "OpenAI"

    private let apiKey: String
    private let client: HTTPClient
    private let logger = Log.providers

    public init(apiKey: String, baseURL: URL? = nil) {
        self.apiKey = apiKey
        self.client = HTTPClient(
            baseURL: baseURL ?? URL(string: "https://api.openai.com")!,
            defaultHeaders: [
                "Authorization": "Bearer \(apiKey)",
                "Content-Type": "application/json",
            ]
        )
    }

    public var supportedModels: [ModelInfo] {
        [
            ModelInfo(id: "gpt-4o", displayName: "GPT-4o", contextWindow: 128_000),
            ModelInfo(id: "gpt-4o-mini", displayName: "GPT-4o Mini", contextWindow: 128_000),
            ModelInfo(id: "o3-mini", displayName: "o3-mini", contextWindow: 200_000),
        ]
    }

    public func validate() async throws -> Bool {
        let _: ModelsResponse = try await client.request(path: "/v1/models")
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
                        OAIMessage(role: msg.role.rawValue, content: msg.content)
                    }

                    let body = ChatCompletionRequest(
                        model: model,
                        messages: apiMessages,
                        max_tokens: options.maxTokens,
                        temperature: options.temperature,
                        stream: true
                    )

                    let bodyData = try JSONEncoder().encode(body)
                    let url = client.baseURL.appendingPathComponent("/v1/chat/completions")

                    let events = SSEStream.stream(
                        url: url,
                        headers: client.defaultHeaders,
                        body: bodyData
                    )

                    for try await event in events {
                        if event.data == "[DONE]" {
                            continuation.yield(.done(.endTurn))
                            break
                        }
                        guard let data = event.data.data(using: .utf8),
                              let chunk = try? JSONDecoder().decode(ChatCompletionChunk.self, from: data),
                              let delta = chunk.choices.first?.delta else { continue }

                        if let content = delta.content {
                            continuation.yield(.text(content))
                        }
                        if let reason = chunk.choices.first?.finish_reason {
                            let stop = reason == "length" ? StopReason.maxTokens : .endTurn
                            continuation.yield(.done(stop))
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

private struct ChatCompletionRequest: Encodable {
    let model: String
    let messages: [OAIMessage]
    let max_tokens: Int
    let temperature: Double?
    let stream: Bool
}

private struct OAIMessage: Codable {
    let role: String
    let content: String
}

private struct ChatCompletionChunk: Decodable {
    let choices: [Choice]
    struct Choice: Decodable {
        let delta: Delta
        let finish_reason: String?
    }
    struct Delta: Decodable {
        let content: String?
    }
}

private struct ModelsResponse: Decodable {
    let data: [ModelEntry]
    struct ModelEntry: Decodable {
        let id: String
    }
}
