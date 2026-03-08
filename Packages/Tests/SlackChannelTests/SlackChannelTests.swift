import XCTest
@testable import SlackChannel
@testable import ChannelKit
@testable import Shared

final class SlackChannelTests: XCTestCase {
    func testSlackConfigDefaults() {
        let config = SlackChannelConfiguration(botToken: "xoxb-123", appToken: "xapp-456", signingSecret: "sec")
        XCTAssertEqual(config.channelID, "slack")
        XCTAssertTrue(config.isEnabled)
        XCTAssertEqual(config.botToken, "xoxb-123")
        XCTAssertEqual(config.webhookPath, "/webhooks/slack")
    }

    func testSlackChannelInit() async {
        let config = SlackChannelConfiguration(botToken: "xoxb-test", appToken: "xapp-test", signingSecret: "secret")
        let channel = SlackChannel(config: config)
        let id = await channel.id
        let name = await channel.displayName
        let status = await channel.status
        let maxLen = await channel.maxTextLength
        XCTAssertEqual(id, "slack")
        XCTAssertEqual(name, "Slack")
        XCTAssertEqual(status, .disconnected)
        XCTAssertEqual(maxLen, Defaults.TextLimits.slack)
    }

    func testSlackConfigCodable() throws {
        let config = SlackChannelConfiguration(botToken: "b", appToken: "a", signingSecret: "s")
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(SlackChannelConfiguration.self, from: data)
        XCTAssertEqual(decoded.botToken, "b")
    }
}
