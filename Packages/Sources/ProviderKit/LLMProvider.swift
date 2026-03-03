// ProviderKit — LLM provider protocol + registry
import Shared

public protocol LLMProvider: Sendable {
    var id: String { get }
    var models: [String] { get }
    func complete(
        _ messages: [ChatMessage],
        model: String
    ) -> AsyncThrowingStream<StreamEvent, Error>
}

public enum StreamEvent: Sendable {
    case text(String)
    case done
}
