import Foundation

// MARK: - Protocol

public protocol StreamParser: Sendable {
    func parse(line: String) -> AgentStreamEvent?
}

// MARK: - Claude Stream JSON Schema

private struct ClaudeStreamMessage: Decodable {
    let type: String
    let message: ClaudeMessage?
    let name: String?
    let input: AnyCodableValue?
    let content: AnyCodableValue?
    let result: String?
    let session_id: String?

    enum CodingKeys: String, CodingKey {
        case type, message, name, input, content, result, session_id
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        message = try? container.decodeIfPresent(ClaudeMessage.self, forKey: .message)
        name = try? container.decodeIfPresent(String.self, forKey: .name)
        input = try? container.decodeIfPresent(AnyCodableValue.self, forKey: .input)
        content = try? container.decodeIfPresent(AnyCodableValue.self, forKey: .content)
        result = try? container.decodeIfPresent(String.self, forKey: .result)
        session_id = try? container.decodeIfPresent(String.self, forKey: .session_id)
    }
}

private struct ClaudeMessage: Decodable {
    let content: [ClaudeContentBlock]?
}

private struct ClaudeContentBlock: Decodable {
    let type: String?
    let text: String?
}

/// Represents a loosely-typed JSON value for fields we don't fully decode.
private enum AnyCodableValue: Decodable {
    case string(String)
    case other

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let str = try? container.decode(String.self) {
            self = .string(str)
        } else {
            // Consume the value so decoding doesn't fail
            _ = try? container.decode(CodablePassthrough.self)
            self = .other
        }
    }

    var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }
}

/// Consumes any JSON value without keeping it.
private struct CodablePassthrough: Decodable {}

// MARK: - ClaudeStreamParser

public struct ClaudeStreamParser: StreamParser {
    public init() {}

    public func parse(line: String) -> AgentStreamEvent? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let data = trimmed.data(using: .utf8) else { return nil }

        guard let msg = try? JSONDecoder().decode(ClaudeStreamMessage.self, from: data) else {
            return nil
        }

        switch msg.type {
        case "assistant":
            let text = msg.message?.content?
                .compactMap(\.text)
                .joined(separator: "") ?? ""
            guard !text.isEmpty else { return nil }
            return .text(text)

        case "tool_use":
            let name = msg.name ?? "unknown"
            let inputStr: String
            if let val = msg.input?.stringValue {
                inputStr = val
            } else if let inputData = trimmed.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: inputData) as? [String: Any],
                      let inputObj = json["input"],
                      let serialized = try? JSONSerialization.data(withJSONObject: inputObj),
                      let str = String(data: serialized, encoding: .utf8)
            {
                inputStr = str
            } else {
                inputStr = "{}"
            }
            return .toolUse(name: name, input: inputStr)

        case "tool_result":
            let content = msg.content?.stringValue ?? ""
            return .toolResult(content)

        case "result":
            let summary = msg.result ?? ""
            return .done(summary: summary, sessionID: msg.session_id)

        default:
            return .progress(msg.type)
        }
    }
}

// MARK: - Codex Stream JSON Schema

private struct CodexStreamMessage: Decodable {
    let type: String
    let content: String?
    let name: String?
    let arguments: String?
}

// MARK: - CodexStreamParser

public struct CodexStreamParser: StreamParser {
    public init() {}

    public func parse(line: String) -> AgentStreamEvent? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let data = trimmed.data(using: .utf8) else { return nil }

        guard let msg = try? JSONDecoder().decode(CodexStreamMessage.self, from: data) else {
            return nil
        }

        switch msg.type {
        case "message":
            let content = msg.content ?? ""
            guard !content.isEmpty else { return nil }
            return .text(content)

        case "function_call":
            let name = msg.name ?? "unknown"
            let args = msg.arguments ?? "{}"
            return .toolUse(name: name, input: args)

        default:
            return .progress(msg.type)
        }
    }
}
