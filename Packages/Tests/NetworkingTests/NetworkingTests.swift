import XCTest
@testable import Networking

final class NetworkingTests: XCTestCase {

    func testHTTPClientInit() {
        let url = URL(string: "https://api.example.com")!
        let client = HTTPClient(baseURL: url, defaultHeaders: ["Authorization": "Bearer tok"])
        XCTAssertEqual(client.baseURL, url)
        XCTAssertEqual(client.defaultHeaders["Authorization"], "Bearer tok")
    }

    func testHTTPClientDefaultHeaders() {
        let client = HTTPClient(baseURL: URL(string: "https://example.com")!)
        XCTAssertTrue(client.defaultHeaders.isEmpty)
    }

    func testHTTPMethodRawValues() {
        XCTAssertEqual(HTTPMethod.get.rawValue, "GET")
        XCTAssertEqual(HTTPMethod.post.rawValue, "POST")
        XCTAssertEqual(HTTPMethod.put.rawValue, "PUT")
        XCTAssertEqual(HTTPMethod.patch.rawValue, "PATCH")
        XCTAssertEqual(HTTPMethod.delete.rawValue, "DELETE")
    }

    func testSSEEventCreation() {
        let event = SSEEvent(event: "message", data: "hello", id: "1")
        XCTAssertEqual(event.event, "message")
        XCTAssertEqual(event.data, "hello")
        XCTAssertEqual(event.id, "1")
    }

    func testSSEEventDefaults() {
        let event = SSEEvent(data: "test")
        XCTAssertNil(event.event)
        XCTAssertEqual(event.data, "test")
        XCTAssertNil(event.id)
    }
}
