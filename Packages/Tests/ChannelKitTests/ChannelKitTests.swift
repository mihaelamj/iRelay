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
}
