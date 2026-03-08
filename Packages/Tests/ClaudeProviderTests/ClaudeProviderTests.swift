import XCTest
@testable import ClaudeProvider
@testable import ProviderKit

final class ClaudeProviderTests: XCTestCase {
    func testClaudeProviderInit() {
        let provider = ClaudeProvider(apiKey: "test-key")
        XCTAssertEqual(provider.id, "claude")
        XCTAssertEqual(provider.displayName, "Anthropic Claude")
    }

    func testSupportedModels() {
        let provider = ClaudeProvider(apiKey: "test-key")
        let models = provider.supportedModels
        XCTAssertFalse(models.isEmpty)
        XCTAssertTrue(models.contains(where: { $0.id.contains("claude") }))
        for model in models {
            XCTAssertGreaterThan(model.contextWindow, 0)
            XCTAssertTrue(model.supportsStreaming)
        }
    }

    func testCustomBaseURL() {
        let url = URL(string: "https://custom.api.com")!
        let provider = ClaudeProvider(apiKey: "key", baseURL: url)
        XCTAssertEqual(provider.id, "claude")
    }
}
