import Foundation
import Shared

// MARK: - Server-Sent Events

public struct SSEEvent: Sendable {
    public let event: String?
    public let data: String
    public let id: String?

    public init(event: String? = nil, data: String, id: String? = nil) {
        self.event = event
        self.data = data
        self.id = id
    }
}

// MARK: - SSE Stream

public struct SSEStream: Sendable {

    /// Open an SSE connection and return an async stream of events.
    public static func stream(
        url: URL,
        headers: [String: String] = [:],
        body: Data? = nil,
        session: URLSession = .shared
    ) -> AsyncThrowingStream<SSEEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = URLRequest(url: url)
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    for (key, value) in headers {
                        request.setValue(value, forHTTPHeaderField: key)
                    }
                    if let body {
                        request.httpMethod = "POST"
                        request.httpBody = body
                        if request.value(forHTTPHeaderField: "Content-Type") == nil {
                            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                        }
                    }

                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse,
                          (200..<300).contains(http.statusCode) else {
                        throw IRelayError.streamingFailed("HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
                    }

                    var currentEvent: String?
                    var currentData: [String] = []
                    var currentID: String?

                    for try await line in bytes.lines {
                        if line.isEmpty {
                            // Dispatch event
                            if !currentData.isEmpty {
                                let event = SSEEvent(
                                    event: currentEvent,
                                    data: currentData.joined(separator: "\n"),
                                    id: currentID
                                )
                                continuation.yield(event)
                            }
                            currentEvent = nil
                            currentData = []
                            currentID = nil
                            continue
                        }

                        if line.hasPrefix("event:") {
                            currentEvent = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                        } else if line.hasPrefix("data:") {
                            currentData.append(String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces))
                        } else if line.hasPrefix("id:") {
                            currentID = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                        }
                        // Ignore "retry:" and comments (lines starting with ":")
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}
