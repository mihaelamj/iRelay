import XCTest
@testable import ChannelKit
@testable import Shared

final class ChannelKitTests: XCTestCase {

    func testChannelStatusDisconnected() {
        let status = ChannelStatus.disconnected
        XCTAssertFalse(status.isConnected)
    }

    func testChannelStatusConnecting() {
        let status = ChannelStatus.connecting
        XCTAssertFalse(status.isConnected)
    }

    func testChannelStatusConnected() {
        let status = ChannelStatus.connected
        XCTAssertTrue(status.isConnected)
    }

    func testChannelStatusReconnecting() {
        let status = ChannelStatus.reconnecting(attempt: 3)
        XCTAssertFalse(status.isConnected)
        if case .reconnecting(let attempt) = status {
            XCTAssertEqual(attempt, 3)
        } else { XCTFail("Expected .reconnecting") }
    }

    func testChannelStatusError() {
        let status = ChannelStatus.error("timeout")
        XCTAssertFalse(status.isConnected)
        if case .error(let msg) = status {
            XCTAssertEqual(msg, "timeout")
        } else { XCTFail("Expected .error") }
    }

    func testChannelStatusEquatable() {
        XCTAssertEqual(ChannelStatus.connected, ChannelStatus.connected)
        XCTAssertEqual(ChannelStatus.disconnected, ChannelStatus.disconnected)
        XCTAssertNotEqual(ChannelStatus.connected, ChannelStatus.disconnected)
        XCTAssertEqual(ChannelStatus.reconnecting(attempt: 1), ChannelStatus.reconnecting(attempt: 1))
        XCTAssertNotEqual(ChannelStatus.reconnecting(attempt: 1), ChannelStatus.reconnecting(attempt: 2))
    }

    func testChannelRegistryEmpty() async {
        let registry = ChannelRegistry()
        let ids = await registry.ids
        XCTAssertTrue(ids.isEmpty)
        let all = await registry.all
        XCTAssertTrue(all.isEmpty)
        let ch = await registry.channel(for: "nonexistent")
        XCTAssertNil(ch)
    }

    // MARK: - ChannelCapabilities

    func testCapabilitiesTextOnly() {
        let caps: ChannelCapabilities = .textOnly
        XCTAssertTrue(caps.contains(.text))
        XCTAssertFalse(caps.contains(.images))
        XCTAssertFalse(caps.contains(.video))
    }

    func testCapabilitiesMultimedia() {
        let caps: ChannelCapabilities = .multimedia
        XCTAssertTrue(caps.contains(.text))
        XCTAssertTrue(caps.contains(.images))
        XCTAssertTrue(caps.contains(.video))
        XCTAssertTrue(caps.contains(.audio))
        XCTAssertTrue(caps.contains(.files))
        XCTAssertTrue(caps.contains(.links))
        XCTAssertFalse(caps.contains(.reactions))
        XCTAssertFalse(caps.contains(.typing))
    }

    func testCapabilitiesFull() {
        let caps: ChannelCapabilities = .full
        XCTAssertTrue(caps.contains(.text))
        XCTAssertTrue(caps.contains(.images))
        XCTAssertTrue(caps.contains(.reactions))
        XCTAssertTrue(caps.contains(.typing))
        XCTAssertFalse(caps.contains(.readReceipts))
        XCTAssertFalse(caps.contains(.threads))
    }

    func testCapabilitiesOptionSetOperations() {
        var caps: ChannelCapabilities = [.text, .images]
        caps.insert(.video)
        XCTAssertTrue(caps.contains(.video))
        caps.remove(.images)
        XCTAssertFalse(caps.contains(.images))

        let union = ChannelCapabilities.textOnly.union(.multimedia)
        XCTAssertTrue(union.contains(.files))

        let intersection = ChannelCapabilities.full.intersection(.multimedia)
        XCTAssertTrue(intersection.contains(.links))
        XCTAssertFalse(intersection.contains(.reactions))
    }

    func testCapabilitiesRawValues() {
        XCTAssertEqual(ChannelCapabilities.text.rawValue, 1)
        XCTAssertEqual(ChannelCapabilities.images.rawValue, 2)
        XCTAssertEqual(ChannelCapabilities.video.rawValue, 4)
        XCTAssertEqual(ChannelCapabilities.audio.rawValue, 8)
    }

    // MARK: - ChannelLimits

    func testLimitsDefault() {
        let limits = ChannelLimits.default
        XCTAssertEqual(limits.maxTextLength, Defaults.TextLimits.default)
        XCTAssertNil(limits.maxImageSize)
        XCTAssertNil(limits.maxVideoSize)
        XCTAssertNil(limits.maxFileSize)
    }

    func testLimitsIMessage() {
        let limits = ChannelLimits.imessage
        XCTAssertEqual(limits.maxTextLength, Defaults.TextLimits.iMessage)
        XCTAssertEqual(limits.maxImageSize, 100_000_000)
        XCTAssertEqual(limits.maxVideoSize, 100_000_000)
        XCTAssertTrue(limits.supportedImageFormats.contains("image/heic"))
        XCTAssertTrue(limits.supportedVideoFormats.contains("video/quicktime"))
    }

    func testLimitsWhatsApp() {
        let limits = ChannelLimits.whatsapp
        XCTAssertEqual(limits.maxTextLength, Defaults.TextLimits.whatsApp)
        XCTAssertEqual(limits.maxImageSize, 5_000_000)
        XCTAssertEqual(limits.maxVideoSize, 16_000_000)
        XCTAssertTrue(limits.supportedVideoFormats.contains("video/3gpp"))
        XCTAssertFalse(limits.supportedImageFormats.contains("image/heic"))
    }

    func testLimitsTelegram() {
        let limits = ChannelLimits.telegram
        XCTAssertEqual(limits.maxTextLength, Defaults.TextLimits.telegram)
        XCTAssertEqual(limits.maxImageSize, 10_000_000)
        XCTAssertEqual(limits.maxVideoSize, 50_000_000)
        XCTAssertEqual(limits.maxFileSize, 50_000_000)
    }

    func testLimitsCustomInit() {
        let limits = ChannelLimits(
            maxTextLength: 1000,
            maxImageSize: 2_000_000,
            supportedImageFormats: ["image/webp"]
        )
        XCTAssertEqual(limits.maxTextLength, 1000)
        XCTAssertEqual(limits.maxImageSize, 2_000_000)
        XCTAssertNil(limits.maxVideoSize)
        XCTAssertNil(limits.maxFileSize)
        XCTAssertTrue(limits.supportedImageFormats.contains("image/webp"))
        XCTAssertEqual(limits.supportedVideoFormats, ["video/mp4"])
    }
}
