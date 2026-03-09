#if os(macOS)
import Foundation

// MARK: - Attributed Body Parser

/// Extracts text from NSKeyedArchiver-encoded attributedBody blobs in chat.db.
///
/// macOS Ventura+ moved message text from the `text` column to `attributedBody`
/// (NSKeyedArchiver-encoded NSAttributedString).
enum AttributedBodyParser {

    /// Parse message text with priority: text column > attributedBody > nil.
    static func parseMessageText(text: String?, attributedBody: Data?) -> String? {
        if let text, !text.isEmpty { return text }
        if let body = attributedBody { return extractText(from: body) }
        return nil
    }

    /// Extract plain text from an NSKeyedArchiver-encoded NSAttributedString.
    static func extractText(from data: Data) -> String? {
        // Try NSKeyedUnarchiver first (reliable on macOS)
        if let attributed = try? NSKeyedUnarchiver.unarchivedObject(
            ofClasses: [
                NSAttributedString.self,
                NSMutableAttributedString.self,
                NSString.self,
                NSMutableString.self,
                NSArray.self,
                NSMutableArray.self,
                NSDictionary.self,
                NSMutableDictionary.self,
                NSNumber.self,
                NSData.self,
                NSMutableData.self,
                NSSet.self,
                NSMutableSet.self,
                NSURL.self,
                NSValue.self,
            ],
            from: data
        ) as? NSAttributedString {
            let result = attributed.string.trimmingCharacters(in: .whitespacesAndNewlines)
            return result.isEmpty ? nil : result
        }

        // Fallback: binary scan for readable text content
        return binaryScanForText(in: data)
    }

    // MARK: - Binary Fallback

    /// Heuristic extraction of text from NSKeyedArchiver data when unarchiving fails.
    /// Looks for the NSString content marker within the binary plist.
    private static func binaryScanForText(in data: Data) -> String? {
        // NSKeyedArchiver embeds NSString values; look for the longest UTF-8 run
        // that isn't a class name or key name.
        guard data.count > 20 else { return nil }

        // Convert to string and look for the content between specific markers
        // The attributedBody typically contains "NSString" followed by the actual text
        let bytes = [UInt8](data)
        var candidates: [String] = []

        var current = Data()
        for byte in bytes {
            if byte >= 0x20, byte < 0x7F || byte >= 0xC0 {
                // Printable ASCII or UTF-8 continuation
                current.append(byte)
            } else {
                if current.count >= 4,
                   let str = String(data: current, encoding: .utf8) {
                    let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty,
                       !isKnownKey(trimmed) {
                        candidates.append(trimmed)
                    }
                }
                current = Data()
            }
        }

        // Check final run
        if current.count >= 4,
           let str = String(data: current, encoding: .utf8) {
            let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, !isKnownKey(trimmed) {
                candidates.append(trimmed)
            }
        }

        // Return the longest candidate that looks like actual message text
        return candidates
            .filter { $0.count >= 2 }
            .max(by: { $0.count < $1.count })
    }

    /// Filter out known NSKeyedArchiver internal keys and class names.
    private static func isKnownKey(_ str: String) -> Bool {
        let knownPrefixes = [
            "NS", "$class", "$archiver", "$objects", "$top",
            "NSAttributes", "NSString", "NSMutable", "NSObject",
            "NSDictionary", "NSArray", "NSNumber", "NSValue",
            "NSAttributedString", "NSURL", "NSData", "NSSet",
            "__kIM", "com.apple",
        ]
        return knownPrefixes.contains { str.hasPrefix($0) }
    }
}
#endif
