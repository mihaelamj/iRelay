import XCTest
@testable import ClawSecurity

final class ClawSecurityTests: XCTestCase {
    func testKeychainStoreInit() {
        let store = KeychainStore(service: "com.irelay.test")
        XCTAssertNotNil(store)
    }

    func testKeychainStoreDefaultService() {
        let store = KeychainStore()
        XCTAssertNotNil(store)
    }
}
