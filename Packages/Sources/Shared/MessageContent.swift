import Foundation

public enum MessageContent: Sendable {
    case text(String)
    case image(Data, mimeType: String)
    case video(Data, mimeType: String)
    case audio(Data, mimeType: String)
    case file(Data, filename: String, mimeType: String)
    case link(URL, title: String?)
    case location(latitude: Double, longitude: Double)
    case compound([MessageContent])
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

    public var isMedia: Bool {
        switch self {
        case .image, .video, .audio, .file:
            return true
        default:
            return false
        }
    }

    /// A text representation for channels that only support text.
    public var textFallback: String {
        switch self {
        case .text(let value):
            return value
        case .image(_, let mimeType):
            return "[Image: \(mimeType)]"
        case .video(_, let mimeType):
            return "[Video: \(mimeType)]"
        case .audio(_, let mimeType):
            return "[Audio: \(mimeType)]"
        case .file(_, let filename, _):
            return "[File: \(filename)]"
        case .link(let url, let title):
            return title.map { "\($0): \(url.absoluteString)" } ?? url.absoluteString
        case .location(let lat, let lon):
            return "[Location: \(lat), \(lon)]"
        case .compound(let parts):
            return parts.map(\.textFallback).joined(separator: "\n")
        }
    }
}
