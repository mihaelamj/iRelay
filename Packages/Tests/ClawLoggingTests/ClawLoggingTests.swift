import XCTest
import Logging
@testable import ClawLogging

final class ClawLoggingTests: XCTestCase {
    func testBootstrap() {
        Log.bootstrap(level: .debug)
    }

    func testLoggerForSubsystem() {
        let logger = Log.logger(for: "test")
        XCTAssertEqual(logger.label, "com.swiftclaw.test")
    }

    func testConvenienceLoggerLabels() {
        XCTAssertEqual(Log.gateway.label, "com.swiftclaw.gateway")
        XCTAssertEqual(Log.channels.label, "com.swiftclaw.channels")
        XCTAssertEqual(Log.providers.label, "com.swiftclaw.providers")
        XCTAssertEqual(Log.sessions.label, "com.swiftclaw.sessions")
        XCTAssertEqual(Log.agents.label, "com.swiftclaw.agents")
        XCTAssertEqual(Log.storage.label, "com.swiftclaw.storage")
        XCTAssertEqual(Log.delivery.label, "com.swiftclaw.delivery")
        XCTAssertEqual(Log.scheduler.label, "com.swiftclaw.scheduler")
        XCTAssertEqual(Log.cli.label, "com.swiftclaw.cli")
    }

    func testLoggerCanLog() {
        let logger = Log.logger(for: "unit-test")
        logger.info("Info")
        logger.debug("Debug")
        logger.warning("Warning")
        logger.error("Error")
    }
}
