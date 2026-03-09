import Foundation

/// A content block within a ChatMessage, matching Claude/OpenAI multimodal API format.
public enum ContentBlock: Sendable, Codable, Equatable {
    case text(String)
    case image(ImageSource)
    case toolUse(id: String, name: String, input: String)
    case toolResult(toolUseID: String, content: String, isError: Bool)

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case type, text, source
        case id, name, input
        case toolUseID = "tool_use_id"
        case content, isError = "is_error"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "text":
            let text = try container.decode(String.self, forKey: .text)
            self = .text(text)
        case "image":
            let source = try container.decode(ImageSource.self, forKey: .source)
            self = .image(source)
        case "tool_use":
            let id = try container.decode(String.self, forKey: .id)
            let name = try container.decode(String.self, forKey: .name)
            let input = try container.decode(String.self, forKey: .input)
            self = .toolUse(id: id, name: name, input: input)
        case "tool_result":
            let toolUseID = try container.decode(String.self, forKey: .toolUseID)
            let content = try container.decode(String.self, forKey: .content)
            let isError = try container.decodeIfPresent(Bool.self, forKey: .isError) ?? false
            self = .toolResult(toolUseID: toolUseID, content: content, isError: isError)
        default:
            let text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
            self = .text(text)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .text(let text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
        case .image(let source):
            try container.encode("image", forKey: .type)
            try container.encode(source, forKey: .source)
        case .toolUse(let id, let name, let input):
            try container.encode("tool_use", forKey: .type)
            try container.encode(id, forKey: .id)
            try container.encode(name, forKey: .name)
            try container.encode(input, forKey: .input)
        case .toolResult(let toolUseID, let content, let isError):
            try container.encode("tool_result", forKey: .type)
            try container.encode(toolUseID, forKey: .toolUseID)
            try container.encode(content, forKey: .content)
            try container.encode(isError, forKey: .isError)
        }
    }
}

extension ContentBlock {
    /// Extract text content, if this is a text block.
    public var textValue: String? {
        if case .text(let value) = self { return value }
        return nil
    }
}

/// Image source for multimodal content blocks.
public struct ImageSource: Sendable, Codable, Equatable {
    public let type: ImageSourceType
    public let mediaType: String
    public let data: String

    public init(type: ImageSourceType, mediaType: String, data: String) {
        self.type = type
        self.mediaType = mediaType
        self.data = data
    }

    /// Create from raw image data (base64-encodes automatically).
    public init(data imageData: Data, mediaType: String) {
        self.type = .base64
        self.mediaType = mediaType
        self.data = imageData.base64EncodedString()
    }

    /// Create from a URL string.
    public init(url: String, mediaType: String) {
        self.type = .url
        self.mediaType = mediaType
        self.data = url
    }
}

public enum ImageSourceType: String, Sendable, Codable, Equatable {
    case base64
    case url
}
