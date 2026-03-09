import XCTest
import Logging
@testable import ClawLogging

final class ClawLoggingTests: XCTestCase {
    func testBootstrap() {
        Log.bootstrap(level: .debug)
    }

    func testLoggerForSubsystem() {
        let logger = Log.logger(for: "test")
        XCTAssertEqual(logger.label, "com.irelay.test")
    }

    func testConvenienceLoggerLabels() {
        XCTAssertEqual(Log.gateway.label, "com.irelay.gateway")
        XCTAssertEqual(Log.channels.label, "com.irelay.channels")
        XCTAssertEqual(Log.providers.label, "com.irelay.providers")
        XCTAssertEqual(Log.sessions.label, "com.irelay.sessions")
        XCTAssertEqual(Log.agents.label, "com.irelay.agents")
        XCTAssertEqual(Log.storage.label, "com.irelay.storage")
        XCTAssertEqual(Log.delivery.label, "com.irelay.delivery")
        XCTAssertEqual(Log.scheduler.label, "com.irelay.scheduler")
        XCTAssertEqual(Log.cli.label, "com.irelay.cli")
    }

    func testLoggerCanLog() {
        let logger = Log.logger(for: "unit-test")
        logger.info("Info")
        logger.debug("Debug")
        logger.warning("Warning")
        logger.error("Error")
    }
}
