#if os(macOS)
import XCTest
@testable import IMessageChannel
@testable import ChannelKit
@testable import Shared

final class IMessageChannelTests: XCTestCase {

    // MARK: - Configuration Tests

    func testConfigDefaults() {
        let config = IMessageChannelConfiguration()
        XCTAssertEqual(config.channelID, "imessage")
        XCTAssertTrue(config.isEnabled)
        XCTAssertEqual(config.pollInterval, 2.0)
        XCTAssertNil(config.dbPath)
        XCTAssertNil(config.allowlist)
    }

    func testConfigCustomValues() {
        let config = IMessageChannelConfiguration(
            pollInterval: 5.0,
            dbPath: "/tmp/test.db",
            allowlist: ["+15551234567"]
        )
        XCTAssertEqual(config.pollInterval, 5.0)
        XCTAssertEqual(config.dbPath, "/tmp/test.db")
        XCTAssertEqual(config.allowlist, ["+15551234567"])
    }

    func testConfigCodable() throws {
        let config = IMessageChannelConfiguration(
            pollInterval: 3.0,
            dbPath: "/custom/path.db",
            allowlist: ["user1", "user2"]
        )
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(IMessageChannelConfiguration.self, from: data)
        XCTAssertEqual(decoded.channelID, "imessage")
        XCTAssertEqual(decoded.pollInterval, 3.0)
        XCTAssertEqual(decoded.dbPath, "/custom/path.db")
        XCTAssertEqual(decoded.allowlist, ["user1", "user2"])
    }

    // MARK: - Channel Init Tests

    func testChannelInit() async {
        let channel = IMessageChannel()
        let id = await channel.id
        let name = await channel.displayName
        let status = await channel.status
        XCTAssertEqual(id, "imessage")
        XCTAssertEqual(name, "iMessage")
        XCTAssertEqual(status, .disconnected)
    }

    func testChannelCapabilities() async {
        let channel = IMessageChannel()
        let caps = channel.capabilities
        XCTAssertTrue(caps.contains(.text))
        XCTAssertTrue(caps.contains(.images))
        XCTAssertTrue(caps.contains(.video))
        XCTAssertTrue(caps.contains(.audio))
        XCTAssertTrue(caps.contains(.files))
        XCTAssertTrue(caps.contains(.links))
        XCTAssertEqual(caps, .multimedia)
    }

    func testChannelLimits() async {
        let channel = IMessageChannel()
        let lim = channel.limits
        XCTAssertEqual(lim.maxTextLength, Defaults.TextLimits.iMessage)
        XCTAssertEqual(lim.maxImageSize, 100_000_000)
        XCTAssertTrue(lim.supportedImageFormats.contains("image/heic"))
        XCTAssertTrue(lim.supportedVideoFormats.contains("video/quicktime"))
    }

    // MARK: - AttributedBodyParser Tests

    func testParseMessageTextPrefersTextColumn() {
        let result = AttributedBodyParser.parseMessageText(text: "Hello", attributedBody: nil)
        XCTAssertEqual(result, "Hello")
    }

    func testParseMessageTextFallsBackToAttributedBody() {
        // Create a simple NSKeyedArchiver-encoded NSAttributedString
        let attrStr = NSAttributedString(string: "From attributed body")
        let data = try! NSKeyedArchiver.archivedData(withRootObject: attrStr, requiringSecureCoding: false)
        let result = AttributedBodyParser.parseMessageText(text: nil, attributedBody: data)
        XCTAssertEqual(result, "From attributed body")
    }

    func testParseMessageTextReturnsNilForBothNil() {
        let result = AttributedBodyParser.parseMessageText(text: nil, attributedBody: nil)
        XCTAssertNil(result)
    }

    func testParseMessageTextReturnsNilForEmptyText() {
        let result = AttributedBodyParser.parseMessageText(text: "", attributedBody: nil)
        XCTAssertNil(result)
    }

    func testParseMessageTextPrefersTextOverBody() {
        let attrStr = NSAttributedString(string: "Body text")
        let data = try! NSKeyedArchiver.archivedData(withRootObject: attrStr, requiringSecureCoding: false)
        let result = AttributedBodyParser.parseMessageText(text: "Column text", attributedBody: data)
        XCTAssertEqual(result, "Column text")
    }

    func testExtractTextFromValidAttributedString() {
        let attrStr = NSAttributedString(string: "Test message content")
        let data = try! NSKeyedArchiver.archivedData(withRootObject: attrStr, requiringSecureCoding: false)
        let result = AttributedBodyParser.extractText(from: data)
        XCTAssertEqual(result, "Test message content")
    }

    func testExtractTextFromEmptyAttributedString() {
        let attrStr = NSAttributedString(string: "")
        let data = try! NSKeyedArchiver.archivedData(withRootObject: attrStr, requiringSecureCoding: false)
        let result = AttributedBodyParser.extractText(from: data)
        XCTAssertNil(result)
    }

    func testExtractTextFromGarbageData() {
        let data = Data([0x00, 0x01, 0x02, 0x03, 0x04])
        let result = AttributedBodyParser.extractText(from: data)
        // Should return nil or a fallback — not crash
        // (binary scan may or may not find text in 5 bytes of garbage)
        _ = result  // Just verify no crash
    }

    // MARK: - IMessageSender Tests

    func testAppleScriptEscaping() {
        let escaped = IMessageSender.escapeAppleScript(#"Hello "world" with \backslash"#)
        XCTAssertEqual(escaped, #"Hello \"world\" with \\backslash"#)
    }

    func testAppleScriptEscapingPlainText() {
        let escaped = IMessageSender.escapeAppleScript("Simple text")
        XCTAssertEqual(escaped, "Simple text")
    }

    func testAppleScriptEscapingEmptyString() {
        let escaped = IMessageSender.escapeAppleScript("")
        XCTAssertEqual(escaped, "")
    }

    // MARK: - MIME Type Extension Tests

    func testFileExtensionJpeg() {
        XCTAssertEqual(IMessageSender.fileExtension(for: "image/jpeg"), "jpg")
    }

    func testFileExtensionPng() {
        XCTAssertEqual(IMessageSender.fileExtension(for: "image/png"), "png")
    }

    func testFileExtensionGif() {
        XCTAssertEqual(IMessageSender.fileExtension(for: "image/gif"), "gif")
    }

    func testFileExtensionHeic() {
        XCTAssertEqual(IMessageSender.fileExtension(for: "image/heic"), "heic")
    }

    func testFileExtensionWebp() {
        XCTAssertEqual(IMessageSender.fileExtension(for: "image/webp"), "webp")
    }

    func testFileExtensionMp4() {
        XCTAssertEqual(IMessageSender.fileExtension(for: "video/mp4"), "mp4")
    }

    func testFileExtensionMov() {
        XCTAssertEqual(IMessageSender.fileExtension(for: "video/quicktime"), "mov")
    }

    func testFileExtensionMp3() {
        XCTAssertEqual(IMessageSender.fileExtension(for: "audio/mpeg"), "mp3")
    }

    func testFileExtensionPdf() {
        XCTAssertEqual(IMessageSender.fileExtension(for: "application/pdf"), "pdf")
    }

    func testFileExtensionUnknown() {
        XCTAssertEqual(IMessageSender.fileExtension(for: "application/x-custom"), "bin")
    }

    // MARK: - Date Conversion Tests

    func testDateFromAppleNanoseconds() {
        // Reference: 2001-01-01 00:00:00 UTC = 0 nanoseconds
        let date = dateFromAppleNanoseconds(0)
        XCTAssertEqual(date.timeIntervalSinceReferenceDate, 0, accuracy: 0.001)
    }

    func testDateFromAppleNanosecondsKnownValue() {
        // 1 second after reference date = 1_000_000_000 nanoseconds
        let date = dateFromAppleNanoseconds(1_000_000_000)
        XCTAssertEqual(date.timeIntervalSinceReferenceDate, 1.0, accuracy: 0.001)
    }

    func testDateFromAppleNanosecondsLargeValue() {
        // 2024-01-01 00:00:00 UTC = 725846400 seconds since 2001
        let nanoseconds: Int64 = 725_846_400 * 1_000_000_000
        let date = dateFromAppleNanoseconds(nanoseconds)
        XCTAssertEqual(date.timeIntervalSinceReferenceDate, 725_846_400, accuracy: 0.001)
    }

    // MARK: - ChatDBReader Cursor Tests

    func testCursorPersistence() throws {
        let tempDir = NSTemporaryDirectory() + "irelay-test-\(UUID().uuidString)"
        let cursorPath = tempDir + "/cursor.txt"
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let reader = ChatDBReader(
            dbPath: "/nonexistent/chat.db",
            cursorPath: cursorPath
        )

        // Initially nil
        XCTAssertNil(reader.loadLastSeenRowID())

        // Save and load
        reader.saveLastSeenRowID(12345)
        XCTAssertEqual(reader.loadLastSeenRowID(), 12345)

        // Overwrite
        reader.saveLastSeenRowID(99999)
        XCTAssertEqual(reader.loadLastSeenRowID(), 99999)
    }
}
#endif
