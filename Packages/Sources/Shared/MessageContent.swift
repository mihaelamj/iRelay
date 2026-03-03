import Foundation

public enum MessageContent: Sendable {
    case text(String)
    case image(Data, mimeType: String)
    case audio(Data, mimeType: String)
    case file(Data, filename: String, mimeType: String)
    case location(latitude: Double, longitude: Double)
}

extension MessageContent {
    public var textValue: String? {
        if case .text(let value) = self { return value }
        return nil
    }

    public var isText: Bool {
        if case .text = self { return true }
        return false
    }
}
