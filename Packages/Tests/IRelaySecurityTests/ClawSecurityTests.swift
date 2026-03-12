import XCTest
@testable import IRelaySecurity

final class IRelaySecurityTests: XCTestCase {
    func testKeychainStoreInit() {
        let store = KeychainStore(service: "com.irelay.test")
        XCTAssertNotNil(store)
    }

    func testKeychainStoreDefaultService() {
        let store = KeychainStore()
        XCTAssertNotNil(store)
    }
}
