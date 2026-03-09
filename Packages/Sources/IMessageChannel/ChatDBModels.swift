#if os(macOS)
import Foundation
import GRDB

// MARK: - Raw Message Row

/// Raw message row from chat.db (READ-ONLY, never write).
struct RawMessageRow: FetchableRecord, Decodable {
    let rowID: Int64
    let guid: String
    let text: String?
    let attributedBody: Data?
    let date: Int64
    let isFromMe: Bool
    let cacheHasAttachments: Bool
    let associatedMessageType: Int
    let senderID: String?

    enum CodingKeys: String, CodingKey {
        case rowID = "ROWID"
        case guid
        case text
        case attributedBody
        case date
        case isFromMe = "is_from_me"
        case cacheHasAttachments = "cache_has_attachments"
        case associatedMessageType = "associated_message_type"
        case senderID = "sender_id"
    }
}

// MARK: - Attachment Row

/// Attachment metadata from chat.db.
struct AttachmentRow: FetchableRecord, Decodable {
    let filename: String?
    let mimeType: String?
    let totalBytes: Int64
    let transferName: String?

    enum CodingKeys: String, CodingKey {
        case filename
        case mimeType = "mime_type"
        case totalBytes = "total_bytes"
        case transferName = "transfer_name"
    }
}

// MARK: - Parsed Message

/// A fully parsed message ready for conversion to InboundMessage.
struct ParsedMessage: Sendable {
    let rowID: Int64
    let guid: String
    let text: String?
    let senderID: String
    let timestamp: Date
    let attachments: [ParsedAttachment]
}

// MARK: - Parsed Attachment

/// A resolved attachment with file data loaded.
struct ParsedAttachment: Sendable {
    let filename: String
    let mimeType: String
    let data: Data
}

// MARK: - Date Conversion

/// Apple epoch nanoseconds (since 2001-01-01) to Date.
func dateFromAppleNanoseconds(_ nanoseconds: Int64) -> Date {
    Date(timeIntervalSinceReferenceDate: Double(nanoseconds) / 1_000_000_000)
}
#endif
