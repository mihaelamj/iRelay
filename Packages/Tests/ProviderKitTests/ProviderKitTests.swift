import XCTest
@testable import ProviderKit
@testable import Shared

final class ProviderKitTests: XCTestCase {

    // MARK: - CompletionOptions

    func testCompletionOptionsDefaults() {
        let opts = CompletionOptions()
        XCTAssertEqual(opts.maxTokens, 4096)
        XCTAssertNil(opts.temperature)
        XCTAssertNil(opts.topP)
        XCTAssertTrue(opts.stopSequences.isEmpty)
        XCTAssertNil(opts.systemPrompt)
        XCTAssertTrue(opts.tools.isEmpty)
        XCTAssertEqual(opts.thinkingLevel, .off)
    }

    func testCompletionOptionsCustom() {
        let opts = CompletionOptions(maxTokens: 1024, temperature: 0.7, topP: 0.9,
                                     stopSequences: ["STOP"], systemPrompt: "Be helpful",
                                     thinkingLevel: .high)
        XCTAssertEqual(opts.maxTokens, 1024)
        XCTAssertEqual(opts.temperature, 0.7)
        XCTAssertEqual(opts.topP, 0.9)
        XCTAssertEqual(opts.stopSequences, ["STOP"])
        XCTAssertEqual(opts.systemPrompt, "Be helpful")
        XCTAssertEqual(opts.thinkingLevel, .high)
    }

    // MARK: - ToolDefinition

    func testToolDefinition() {
        let tool = ToolDefinition(name: "search", description: "Search the web",
                                  inputSchema: "{\"type\":\"object\"}")
        XCTAssertEqual(tool.name, "search")
        XCTAssertEqual(tool.description, "Search the web")
        XCTAssertTrue(tool.inputSchema.contains("object"))
    }

    func testToolDefinitionCodable() throws {
        let tool = ToolDefinition(name: "calc", description: "Calculate", inputSchema: "{}")
        let data = try JSONEncoder().encode(tool)
        let decoded = try JSONDecoder().decode(ToolDefinition.self, from: data)
        XCTAssertEqual(decoded.name, "calc")
    }

    // MARK: - ToolCall

    func testToolCall() {
        let call = ToolCall(id: "tc-1", name: "search", input: "{\"q\":\"hello\"}")
        XCTAssertEqual(call.id, "tc-1")
        XCTAssertEqual(call.name, "search")
        XCTAssertTrue(call.input.contains("hello"))
    }

    // MARK: - ModelInfo

    func testModelInfo() {
        let model = ModelInfo(id: "gpt-4", displayName: "GPT-4", contextWindow: 128000)
        XCTAssertEqual(model.id, "gpt-4")
        XCTAssertEqual(model.contextWindow, 128000)
        XCTAssertTrue(model.supportsTools)
        XCTAssertTrue(model.supportsStreaming)
    }

    func testModelInfoCustomFlags() {
        let model = ModelInfo(id: "m1", displayName: "M1", contextWindow: 4096,
                              supportsTools: false, supportsStreaming: false)
        XCTAssertFalse(model.supportsTools)
        XCTAssertFalse(model.supportsStreaming)
    }

    // MARK: - TokenUsage

    func testTokenUsage() {
        let usage = TokenUsage(inputTokens: 100, outputTokens: 50)
        XCTAssertEqual(usage.inputTokens, 100)
        XCTAssertEqual(usage.outputTokens, 50)
        XCTAssertEqual(usage.totalTokens, 150)
    }

    func testTokenUsageZero() {
        let usage = TokenUsage(inputTokens: 0, outputTokens: 0)
        XCTAssertEqual(usage.totalTokens, 0)
    }

    // MARK: - StopReason

    func testStopReasonRawValues() {
        XCTAssertEqual(StopReason.endTurn.rawValue, "end_turn")
        XCTAssertEqual(StopReason.maxTokens.rawValue, "max_tokens")
        XCTAssertEqual(StopReason.toolUse.rawValue, "tool_use")
        XCTAssertEqual(StopReason.stopSequence.rawValue, "stop_sequence")
    }

    // MARK: - StreamEvent

    func testStreamEventText() {
        let event = StreamEvent.text("hello")
        if case .text(let s) = event {
            XCTAssertEqual(s, "hello")
        } else { XCTFail("Expected .text") }
    }

    func testStreamEventDone() {
        let event = StreamEvent.done(.endTurn)
        if case .done(let reason) = event {
            XCTAssertEqual(reason, .endTurn)
        } else { XCTFail("Expected .done") }
    }

    func testStreamEventError() {
        let event = StreamEvent.error("fail")
        if case .error(let msg) = event {
            XCTAssertEqual(msg, "fail")
        } else { XCTFail("Expected .error") }
    }

    func testStreamEventToolCall() {
        let tc = ToolCall(id: "1", name: "fn", input: "{}")
        let event = StreamEvent.toolCall(tc)
        if case .toolCall(let call) = event {
            XCTAssertEqual(call.name, "fn")
        } else { XCTFail("Expected .toolCall") }
    }

    func testStreamEventUsage() {
        let u = TokenUsage(inputTokens: 10, outputTokens: 20)
        let event = StreamEvent.usage(u)
        if case .usage(let usage) = event {
            XCTAssertEqual(usage.totalTokens, 30)
        } else { XCTFail("Expected .usage") }
    }

    // MARK: - ProviderRegistry

    func testProviderRegistryEmpty() async {
        let registry = ProviderRegistry()
        let ids = await registry.ids
        XCTAssertTrue(ids.isEmpty)
        let all = await registry.all
        XCTAssertTrue(all.isEmpty)
    }
}
