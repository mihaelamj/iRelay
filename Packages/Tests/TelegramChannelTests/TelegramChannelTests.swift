import XCTest
@testable import TelegramChannel
@testable import ChannelKit
@testable import Shared

final class TelegramChannelTests: XCTestCase {
    func testTelegramConfigDefaults() {
        let config = TelegramChannelConfiguration(botToken: "123:ABC")
        XCTAssertEqual(config.channelID, "telegram")
        XCTAssertTrue(config.isEnabled)
        XCTAssertEqual(config.botToken, "123:ABC")
        XCTAssertNil(config.webhookURL)
        XCTAssertEqual(config.pollingTimeout, 30)
    }

    func testTelegramConfigWithWebhook() {
        let config = TelegramChannelConfiguration(botToken: "tok", webhookURL: "https://example.com/webhook")
        XCTAssertEqual(config.webhookURL, "https://example.com/webhook")
    }

    func testTelegramChannelInit() async {
        let config = TelegramChannelConfiguration(botToken: "test-token")
        let channel = TelegramChannel(config: config)
        let id = await channel.id
        let name = await channel.displayName
        let status = await channel.status
        let maxLen = await channel.maxTextLength
        XCTAssertEqual(id, "telegram")
        XCTAssertEqual(name, "Telegram")
        XCTAssertEqual(status, .disconnected)
        XCTAssertEqual(maxLen, Defaults.TextLimits.telegram)
    }

    func testTelegramConfigCodable() throws {
        let config = TelegramChannelConfiguration(botToken: "abc:123")
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(TelegramChannelConfiguration.self, from: data)
        XCTAssertEqual(decoded.botToken, "abc:123")
        XCTAssertEqual(decoded.channelID, "telegram")
    }
}
