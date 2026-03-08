import XCTest
@testable import ClawSecurity

final class ClawSecurityTests: XCTestCase {
    func testKeychainStoreInit() {
        let store = KeychainStore(service: "com.swiftclaw.test")
        XCTAssertNotNil(store)
    }

    func testKeychainStoreDefaultService() {
        let store = KeychainStore()
        XCTAssertNotNil(store)
    }
}
