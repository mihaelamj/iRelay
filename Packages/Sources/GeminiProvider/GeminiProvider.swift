import Foundation
import ProviderKit
import Shared
import Networking
import ClawLogging

// MARK: - Gemini Provider

public struct GeminiProvider: LLMProvider, Sendable {
    public let id = "gemini"
    public let displayName = "Google Gemini"

    private let apiKey: String
    private let client: HTTPClient
    private let logger = Log.providers

    public init(apiKey: String) {
        self.apiKey = apiKey
        self.client = HTTPClient(
            baseURL: URL(string: "https://generativelanguage.googleapis.com")!,
            defaultHeaders: ["Content-Type": "application/json"]
        )
    }

    public var supportedModels: [ModelInfo] {
        [
            ModelInfo(id: "gemini-2.0-flash", displayName: "Gemini 2.0 Flash", contextWindow: 1_000_000),
            ModelInfo(id: "gemini-2.0-pro", displayName: "Gemini 2.0 Pro", contextWindow: 1_000_000),
        ]
    }

    public func validate() async throws -> Bool {
        let _: GeminiModelsResponse = try await client.request(
            path: "/v1beta/models",
            headers: ["x-goog-api-key": apiKey]
        )
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
                    let contents = messages.filter { $0.role != .system }.map { msg in
                        GeminiContent(
                            role: msg.role == .assistant ? "model" : "user",
                            parts: [.init(text: msg.textContent)]
                        )
                    }

                    let systemInstruction: GeminiContent? = if let sys = options.systemPrompt
                        ?? messages.first(where: { $0.role == .system })?.textContent {
                        GeminiContent(role: "user", parts: [.init(text: sys)])
                    } else {
                        nil
                    }

                    let body = GeminiRequest(
                        contents: contents,
                        systemInstruction: systemInstruction,
                        generationConfig: .init(
                            maxOutputTokens: options.maxTokens,
                            temperature: options.temperature
                        )
                    )

                    let bodyData = try JSONEncoder().encode(body)
                    let url = client.baseURL.appendingPathComponent(
                        "/v1beta/models/\(model):streamGenerateContent"
                    )

                    var urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: false)!
                    urlComponents.queryItems = [
                        URLQueryItem(name: "key", value: apiKey),
                        URLQueryItem(name: "alt", value: "sse"),
                    ]

                    let events = SSEStream.stream(
                        url: urlComponents.url!,
                        body: bodyData
                    )

                    for try await event in events {
                        guard let data = event.data.data(using: .utf8),
                              let chunk = try? JSONDecoder().decode(GeminiResponse.self, from: data) else {
                            continue
                        }

                        if let text = chunk.candidates?.first?.content?.parts.first?.text {
                            continuation.yield(.text(text))
                        }
                        if let reason = chunk.candidates?.first?.finishReason, reason == "STOP" {
                            if let usage = chunk.usageMetadata {
                                continuation.yield(.usage(TokenUsage(
                                    inputTokens: usage.promptTokenCount ?? 0,
                                    outputTokens: usage.candidatesTokenCount ?? 0
                                )))
                            }
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

private struct GeminiRequest: Encodable {
    let contents: [GeminiContent]
    let systemInstruction: GeminiContent?
    let generationConfig: GenerationConfig?
}

private struct GeminiContent: Codable {
    let role: String
    let parts: [Part]
    struct Part: Codable {
        let text: String
    }
}

private struct GenerationConfig: Encodable {
    let maxOutputTokens: Int?
    let temperature: Double?
}

private struct GeminiResponse: Decodable {
    let candidates: [Candidate]?
    let usageMetadata: UsageMetadata?

    struct Candidate: Decodable {
        let content: GeminiContent?
        let finishReason: String?
    }

    struct UsageMetadata: Decodable {
        let promptTokenCount: Int?
        let candidatesTokenCount: Int?
    }
}

private struct GeminiModelsResponse: Decodable {
    let models: [GeminiModel]
    struct GeminiModel: Decodable {
        let name: String
    }
}
