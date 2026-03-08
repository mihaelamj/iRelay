import XCTest
@testable import WhatsAppChannel
@testable import ChannelKit
@testable import Shared

final class WhatsAppChannelTests: XCTestCase {
    func testWhatsAppConfigDefaults() {
        let config = WhatsAppChannelConfiguration(phoneNumberID: "123", accessToken: "tok", verifyToken: "vtok")
        XCTAssertEqual(config.channelID, "whatsapp")
        XCTAssertTrue(config.isEnabled)
        XCTAssertEqual(config.phoneNumberID, "123")
        XCTAssertEqual(config.webhookPath, "/webhooks/whatsapp")
    }

    func testWhatsAppChannelInit() async {
        let config = WhatsAppChannelConfiguration(phoneNumberID: "123", accessToken: "tok", verifyToken: "vtok")
        let channel = WhatsAppChannel(config: config)
        let id = await channel.id
        let name = await channel.displayName
        let status = await channel.status
        let maxLen = await channel.maxTextLength
        XCTAssertEqual(id, "whatsapp")
        XCTAssertEqual(name, "WhatsApp")
        XCTAssertEqual(status, .disconnected)
        XCTAssertEqual(maxLen, Defaults.TextLimits.whatsApp)
    }

    func testWhatsAppConfigCodable() throws {
        let config = WhatsAppChannelConfiguration(phoneNumberID: "p1", accessToken: "a", verifyToken: "v")
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(WhatsAppChannelConfiguration.self, from: data)
        XCTAssertEqual(decoded.phoneNumberID, "p1")
    }
}
