#if os(macOS)
import Foundation
import ClawLogging
import Shared

// MARK: - iMessage Sender

/// Sends messages via AppleScript bridge to Messages.app.
public enum IMessageSender {

    private static let logger = Log.channels
    /// Messages.app is sandboxed — it can only access files inside its own Attachments directory.
    private static let tempDirectory = NSHomeDirectory() + "/Library/Messages/Attachments/irelay-send"

    // MARK: - Text Sending

    public static func sendText(_ text: String, to recipient: String) throws {
        let escaped = escapeAppleScript(text)
        let escapedRecipient = escapeAppleScript(recipient)

        let script = """
            tell application "Messages"
                set targetBuddy to buddy "\(escapedRecipient)" of service 1
                send "\(escaped)" to targetBuddy
            end tell
            """

        guard try runAppleScript(script) != nil else {
            throw IRelayError.channelSendFailed(channelID: "imessage", reason: "AppleScript send text failed")
        }
        logger.debug("Sent iMessage text to \(recipient)")
    }

    // MARK: - File Sending

    static func sendFile(at path: URL, to recipient: String) throws {
        let escapedRecipient = escapeAppleScript(recipient)
        let posixPath = path.path

        let script = """
            tell application "Messages"
                set targetBuddy to buddy "\(escapedRecipient)" of service 1
                send (POSIX file "\(posixPath)") to targetBuddy
            end tell
            """

        guard try runAppleScript(script) != nil else {
            throw IRelayError.channelSendFailed(channelID: "imessage", reason: "AppleScript send file failed")
        }
        logger.debug("Sent iMessage file to \(recipient): \(posixPath)")
    }

    // MARK: - MessageContent Sending

    static func send(content: MessageContent, to recipient: String) throws {
        switch content {
        case .text(let text):
            try sendText(text, to: recipient)

        case .image(let data, let mimeType):
            let ext = fileExtension(for: mimeType)
            let url = try writeTempFile(data: data, name: "image.\(ext)")
            defer { try? FileManager.default.removeItem(at: url) }
            try sendFile(at: url, to: recipient)

        case .video(let data, let mimeType):
            let ext = fileExtension(for: mimeType)
            let url = try writeTempFile(data: data, name: "video.\(ext)")
            defer { try? FileManager.default.removeItem(at: url) }
            try sendFile(at: url, to: recipient)

        case .audio(let data, let mimeType):
            let ext = fileExtension(for: mimeType)
            let url = try writeTempFile(data: data, name: "audio.\(ext)")
            defer { try? FileManager.default.removeItem(at: url) }
            try sendFile(at: url, to: recipient)

        case .file(let data, let filename, _):
            let url = try writeTempFile(data: data, name: filename)
            defer { try? FileManager.default.removeItem(at: url) }
            try sendFile(at: url, to: recipient)

        case .link(let url, _):
            try sendText(url.absoluteString, to: recipient)

        case .compound(let parts):
            for part in parts {
                try send(content: part, to: recipient)
            }

        case .location:
            try sendText(content.textFallback, to: recipient)
        }
    }

    // MARK: - Helpers

    static func escapeAppleScript(_ str: String) -> String {
        str.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    static func fileExtension(for mimeType: String) -> String {
        switch mimeType {
        case "image/jpeg": "jpg"
        case "image/png": "png"
        case "image/gif": "gif"
        case "image/heic": "heic"
        case "image/webp": "webp"
        case "video/mp4": "mp4"
        case "video/quicktime": "mov"
        case "audio/mpeg": "mp3"
        case "audio/aac": "aac"
        case "audio/wav": "wav"
        case "application/pdf": "pdf"
        default: "bin"
        }
    }

    private static func writeTempFile(data: Data, name: String) throws -> URL {
        let dir = URL(fileURLWithPath: tempDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let uuid = UUID().uuidString.prefix(8)
        let url = dir.appendingPathComponent("\(uuid)-\(name)")
        try data.write(to: url)
        return url
    }

    private static func runAppleScript(_ source: String) throws -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", source]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
#endif
