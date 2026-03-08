import XCTest
@testable import OpenAIProvider
@testable import ProviderKit

final class OpenAIProviderTests: XCTestCase {
    func testOpenAIProviderInit() {
        let provider = OpenAIProvider(apiKey: "test-key")
        XCTAssertEqual(provider.id, "openai")
        XCTAssertEqual(provider.displayName, "OpenAI")
    }

    func testSupportedModels() {
        let provider = OpenAIProvider(apiKey: "test-key")
        let models = provider.supportedModels
        XCTAssertFalse(models.isEmpty)
        XCTAssertTrue(models.contains(where: { $0.id.contains("gpt") }))
    }

    func testCustomBaseURL() {
        let url = URL(string: "https://custom.openai.com")!
        let provider = OpenAIProvider(apiKey: "key", baseURL: url)
        XCTAssertEqual(provider.id, "openai")
    }
}
