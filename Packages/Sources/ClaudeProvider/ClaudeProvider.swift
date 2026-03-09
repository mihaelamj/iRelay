import Foundation
import ProviderKit
import Shared
import Networking
import ClawLogging

// MARK: - Claude Provider

public struct ClaudeProvider: LLMProvider, Sendable {
    public let id = "claude"
    public let displayName = "Anthropic Claude"

    private let apiKey: String
    private let client: HTTPClient
    private let logger = Log.providers

    public init(apiKey: String, baseURL: URL? = nil) {
        self.apiKey = apiKey
        self.client = HTTPClient(
            baseURL: baseURL ?? URL(string: "https://api.anthropic.com")!,
            defaultHeaders: [
                "x-api-key": apiKey,
                "anthropic-version": "2023-06-01",
                "content-type": "application/json",
            ]
        )
    }

    public var supportedModels: [ModelInfo] {
        [
            ModelInfo(id: "claude-sonnet-4-20250514", displayName: "Claude Sonnet 4", contextWindow: 200_000),
            ModelInfo(id: "claude-opus-4-20250514", displayName: "Claude Opus 4", contextWindow: 200_000),
            ModelInfo(id: "claude-haiku-3-5-20241022", displayName: "Claude Haiku 3.5", contextWindow: 200_000),
        ]
    }

    public func validate() async throws -> Bool {
        // Quick model list check — if auth fails, this throws
        let _: MessageCountResponse = try await client.request(
            path: "/v1/messages/count_tokens",
            method: .post,
            body: CountTokensRequest(
                model: "claude-sonnet-4-20250514",
                messages: [APIMessage(role: "user", content: "hi")]
            )
        )
        return true
    }

    // MARK: - Streaming Completion

    public func complete(
        _ messages: [ChatMessage],
        model: String,
        options: CompletionOptions
    ) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let apiMessages = messages.filter { $0.role != .system }.map { msg in
                        APIMessage(role: msg.role == .assistant ? "assistant" : "user", content: msg.textContent)
                    }

                    let systemPrompt = options.systemPrompt
                        ?? messages.first(where: { $0.role == .system })?.textContent

                    let body = MessagesRequest(
                        model: model,
                        max_tokens: options.maxTokens,
                        system: systemPrompt,
                        messages: apiMessages,
                        stream: true,
                        temperature: options.temperature
                    )

                    let bodyData = try JSONEncoder().encode(body)
                    let url = client.baseURL.appendingPathComponent("/v1/messages")

                    let events = SSEStream.stream(
                        url: url,
                        headers: client.defaultHeaders,
                        body: bodyData
                    )

                    for try await event in events {
                        guard let parsed = parseSSEEvent(event) else { continue }
                        continuation.yield(parsed)
                        if case .done = parsed { break }
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - SSE Event Parsing

    private func parseSSEEvent(_ event: SSEEvent) -> StreamEvent? {
        guard let data = event.data.data(using: .utf8) else { return nil }

        switch event.event {
        case "content_block_delta":
            if let delta = try? JSONDecoder().decode(ContentBlockDelta.self, from: data) {
                if let text = delta.delta.text {
                    return .text(text)
                }
                if let toolInput = delta.delta.partial_json {
                    return .text(toolInput) // accumulate tool input
                }
            }

        case "content_block_start":
            if let block = try? JSONDecoder().decode(ContentBlockStart.self, from: data),
               block.content_block.type == "tool_use" {
                return .toolCall(ToolCall(
                    id: block.content_block.id ?? "",
                    name: block.content_block.name ?? "",
                    input: ""
                ))
            }

        case "message_delta":
            if let delta = try? JSONDecoder().decode(MessageDelta.self, from: data) {
                let reason = StopReason(rawValue: delta.delta.stop_reason ?? "") ?? .endTurn
                if let usage = delta.usage {
                    continuation_yield_usage(usage)
                }
                return .done(reason)
            }

        case "message_start":
            if let start = try? JSONDecoder().decode(MessageStart.self, from: data),
               let usage = start.message.usage {
                return .usage(TokenUsage(inputTokens: usage.input_tokens, outputTokens: 0))
            }

        default:
            break
        }
        return nil
    }

    private func continuation_yield_usage(_ usage: APIUsage) {
        // Usage is reported via message_delta — captured by caller
    }
}

// MARK: - API Types

private struct MessagesRequest: Encodable {
    let model: String
    let max_tokens: Int
    let system: String?
    let messages: [APIMessage]
    let stream: Bool
    let temperature: Double?
}

private struct APIMessage: Codable {
    let role: String
    let content: String
}

private struct CountTokensRequest: Encodable {
    let model: String
    let messages: [APIMessage]
}

private struct MessageCountResponse: Decodable {
    let input_tokens: Int
}

// MARK: - SSE Response Types

private struct ContentBlockDelta: Decodable {
    let delta: Delta
    struct Delta: Decodable {
        let text: String?
        let partial_json: String?
    }
}

private struct ContentBlockStart: Decodable {
    let content_block: ContentBlock
    struct ContentBlock: Decodable {
        let type: String
        let id: String?
        let name: String?
    }
}

private struct MessageDelta: Decodable {
    let delta: Delta
    let usage: APIUsage?
    struct Delta: Decodable {
        let stop_reason: String?
    }
}

private struct MessageStart: Decodable {
    let message: Message
    struct Message: Decodable {
        let usage: APIUsage?
    }
}

private struct APIUsage: Decodable {
    let input_tokens: Int
    let output_tokens: Int
}
