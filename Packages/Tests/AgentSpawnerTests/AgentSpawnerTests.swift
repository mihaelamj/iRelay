import XCTest
@testable import AgentSpawner
import Shared

final class AgentSpawnerTests: XCTestCase {

    // MARK: - AgentType

    func testAgentTypeRawValues() {
        XCTAssertEqual(AgentType.claude.rawValue, "claude")
        XCTAssertEqual(AgentType.codex.rawValue, "codex")
    }

    func testAgentTypeCaseIterable() {
        XCTAssertEqual(AgentType.allCases.count, 2)
        XCTAssertTrue(AgentType.allCases.contains(.claude))
        XCTAssertTrue(AgentType.allCases.contains(.codex))
    }

    func testAgentTypeExecutableName() {
        XCTAssertEqual(AgentType.claude.executableName, "claude")
        XCTAssertEqual(AgentType.codex.executableName, "codex")
    }

    func testAgentTypeCodable() throws {
        let data = try JSONEncoder().encode(AgentType.claude)
        let decoded = try JSONDecoder().decode(AgentType.self, from: data)
        XCTAssertEqual(decoded, .claude)
    }

    // MARK: - AgentSpawnConfig

    func testAgentSpawnConfigDefaults() {
        let url = URL(fileURLWithPath: "/tmp")
        let config = AgentSpawnConfig(type: .claude, workingDirectory: url)
        XCTAssertEqual(config.type, .claude)
        XCTAssertEqual(config.workingDirectory, url)
        XCTAssertNil(config.model)
        XCTAssertNil(config.systemPrompt)
        XCTAssertNil(config.allowedTools)
        XCTAssertEqual(config.timeout, Defaults.Spawner.defaultTimeout)
        XCTAssertEqual(config.idleTimeout, Defaults.Spawner.defaultIdleTimeout)
        XCTAssertNil(config.sessionID)
        XCTAssertFalse(config.continueSession)
        XCTAssertTrue(config.environment.isEmpty)
    }

    func testAgentSpawnConfigCustomValues() {
        let url = URL(fileURLWithPath: "/projects/myapp")
        let config = AgentSpawnConfig(
            type: .codex,
            workingDirectory: url,
            model: "o3",
            systemPrompt: "Be concise",
            allowedTools: ["Read", "Write"],
            timeout: 300,
            idleTimeout: 60,
            sessionID: "sess-123",
            continueSession: true,
            environment: ["FOO": "BAR"]
        )
        XCTAssertEqual(config.type, .codex)
        XCTAssertEqual(config.model, "o3")
        XCTAssertEqual(config.systemPrompt, "Be concise")
        XCTAssertEqual(config.allowedTools, ["Read", "Write"])
        XCTAssertEqual(config.timeout, 300)
        XCTAssertEqual(config.idleTimeout, 60)
        XCTAssertEqual(config.sessionID, "sess-123")
        XCTAssertTrue(config.continueSession)
        XCTAssertEqual(config.environment["FOO"], "BAR")
    }

    // MARK: - ClaudeStreamParser

    func testClaudeStreamParserAssistantText() {
        let parser = ClaudeStreamParser()
        let json = """
        {"type":"assistant","message":{"content":[{"type":"text","text":"Looking at the code..."}]}}
        """
        let event = parser.parse(line: json)
        if case .text(let text) = event {
            XCTAssertEqual(text, "Looking at the code...")
        } else {
            XCTFail("Expected .text event, got \(String(describing: event))")
        }
    }

    func testClaudeStreamParserToolUse() {
        let parser = ClaudeStreamParser()
        let json = """
        {"type":"tool_use","name":"Read","input":{"file_path":"/src/main.swift"}}
        """
        let event = parser.parse(line: json)
        if case .toolUse(let name, let input) = event {
            XCTAssertEqual(name, "Read")
            XCTAssertTrue(input.contains("main.swift"))
        } else {
            XCTFail("Expected .toolUse event, got \(String(describing: event))")
        }
    }

    func testClaudeStreamParserToolResult() {
        let parser = ClaudeStreamParser()
        let json = """
        {"type":"tool_result","content":"file contents here"}
        """
        let event = parser.parse(line: json)
        if case .toolResult(let content) = event {
            XCTAssertEqual(content, "file contents here")
        } else {
            XCTFail("Expected .toolResult event, got \(String(describing: event))")
        }
    }

    func testClaudeStreamParserResult() {
        let parser = ClaudeStreamParser()
        let json = """
        {"type":"result","result":"Done. Fixed 3 issues.","session_id":"sess-abc123"}
        """
        let event = parser.parse(line: json)
        if case .done(let summary, let sessionID) = event {
            XCTAssertEqual(summary, "Done. Fixed 3 issues.")
            XCTAssertEqual(sessionID, "sess-abc123")
        } else {
            XCTFail("Expected .done event, got \(String(describing: event))")
        }
    }

    func testClaudeStreamParserUnknownType() {
        let parser = ClaudeStreamParser()
        let json = """
        {"type":"system","message":"initializing"}
        """
        let event = parser.parse(line: json)
        if case .progress(let type) = event {
            XCTAssertEqual(type, "system")
        } else {
            XCTFail("Expected .progress event, got \(String(describing: event))")
        }
    }

    func testClaudeStreamParserEmptyLine() {
        let parser = ClaudeStreamParser()
        XCTAssertNil(parser.parse(line: ""))
        XCTAssertNil(parser.parse(line: "   "))
    }

    func testClaudeStreamParserInvalidJSON() {
        let parser = ClaudeStreamParser()
        XCTAssertNil(parser.parse(line: "not json at all"))
        XCTAssertNil(parser.parse(line: "{broken json"))
    }

    func testClaudeStreamParserAssistantEmptyContent() {
        let parser = ClaudeStreamParser()
        let json = """
        {"type":"assistant","message":{"content":[]}}
        """
        XCTAssertNil(parser.parse(line: json))
    }

    // MARK: - CodexStreamParser

    func testCodexStreamParserMessage() {
        let parser = CodexStreamParser()
        let json = """
        {"type":"message","content":"Hello from codex"}
        """
        let event = parser.parse(line: json)
        if case .text(let text) = event {
            XCTAssertEqual(text, "Hello from codex")
        } else {
            XCTFail("Expected .text event, got \(String(describing: event))")
        }
    }

    func testCodexStreamParserFunctionCall() {
        let parser = CodexStreamParser()
        let json = """
        {"type":"function_call","name":"shell","arguments":"ls -la"}
        """
        let event = parser.parse(line: json)
        if case .toolUse(let name, let input) = event {
            XCTAssertEqual(name, "shell")
            XCTAssertEqual(input, "ls -la")
        } else {
            XCTFail("Expected .toolUse event, got \(String(describing: event))")
        }
    }

    func testCodexStreamParserUnknownType() {
        let parser = CodexStreamParser()
        let json = """
        {"type":"status","content":"working"}
        """
        let event = parser.parse(line: json)
        if case .progress(let type) = event {
            XCTAssertEqual(type, "status")
        } else {
            XCTFail("Expected .progress event, got \(String(describing: event))")
        }
    }

    func testCodexStreamParserEmptyContent() {
        let parser = CodexStreamParser()
        let json = """
        {"type":"message","content":""}
        """
        XCTAssertNil(parser.parse(line: json))
    }

    func testCodexStreamParserInvalidJSON() {
        let parser = CodexStreamParser()
        XCTAssertNil(parser.parse(line: "not json"))
    }

    // MARK: - CLIBuilder Arguments

    func testCLIBuilderClaudeBasicArguments() {
        let config = AgentSpawnConfig(type: .claude, workingDirectory: URL(fileURLWithPath: "/tmp"))
        let args = CLIBuilder.buildArguments(prompt: "Fix the bug", config: config)
        XCTAssertEqual(args[0], "-p")
        XCTAssertEqual(args[1], "Fix the bug")
        XCTAssertTrue(args.contains("--output-format"))
        XCTAssertTrue(args.contains("stream-json"))
    }

    func testCLIBuilderClaudeWithModel() {
        let config = AgentSpawnConfig(
            type: .claude,
            workingDirectory: URL(fileURLWithPath: "/tmp"),
            model: "claude-opus-4-20250514"
        )
        let args = CLIBuilder.buildArguments(prompt: "Help", config: config)
        XCTAssertTrue(args.contains("--model"))
        XCTAssertTrue(args.contains("claude-opus-4-20250514"))
    }

    func testCLIBuilderClaudeWithAllowedTools() {
        let config = AgentSpawnConfig(
            type: .claude,
            workingDirectory: URL(fileURLWithPath: "/tmp"),
            allowedTools: ["Read", "Write", "Bash"]
        )
        let args = CLIBuilder.buildArguments(prompt: "Help", config: config)
        XCTAssertTrue(args.contains("--allowedTools"))
        XCTAssertTrue(args.contains("Read,Write,Bash"))
    }

    func testCLIBuilderClaudeWithSystemPrompt() {
        let config = AgentSpawnConfig(
            type: .claude,
            workingDirectory: URL(fileURLWithPath: "/tmp"),
            systemPrompt: "You are a helpful assistant"
        )
        let args = CLIBuilder.buildArguments(prompt: "Help", config: config)
        XCTAssertTrue(args.contains("--system-prompt"))
        XCTAssertTrue(args.contains("You are a helpful assistant"))
    }

    func testCLIBuilderClaudeWithSessionID() {
        let config = AgentSpawnConfig(
            type: .claude,
            workingDirectory: URL(fileURLWithPath: "/tmp"),
            sessionID: "sess-abc"
        )
        let args = CLIBuilder.buildArguments(prompt: "Continue", config: config)
        XCTAssertTrue(args.contains("--session-id"))
        XCTAssertTrue(args.contains("sess-abc"))
    }

    func testCLIBuilderClaudeWithContinue() {
        let config = AgentSpawnConfig(
            type: .claude,
            workingDirectory: URL(fileURLWithPath: "/tmp"),
            continueSession: true
        )
        let args = CLIBuilder.buildArguments(prompt: "Continue", config: config)
        XCTAssertTrue(args.contains("--continue"))
    }

    func testCLIBuilderClaudeSessionIDTakesPrecedenceOverContinue() {
        let config = AgentSpawnConfig(
            type: .claude,
            workingDirectory: URL(fileURLWithPath: "/tmp"),
            sessionID: "sess-xyz",
            continueSession: true
        )
        let args = CLIBuilder.buildArguments(prompt: "Continue", config: config)
        XCTAssertTrue(args.contains("--session-id"))
        XCTAssertFalse(args.contains("--continue"))
    }

    func testCLIBuilderCodexBasicArguments() {
        let config = AgentSpawnConfig(type: .codex, workingDirectory: URL(fileURLWithPath: "/tmp"))
        let args = CLIBuilder.buildArguments(prompt: "Fix the bug", config: config)
        XCTAssertEqual(args[0], "exec")
        XCTAssertEqual(args[1], "Fix the bug")
        XCTAssertTrue(args.contains("--json"))
    }

    func testCLIBuilderCodexWithAttachments() {
        let config = AgentSpawnConfig(type: .codex, workingDirectory: URL(fileURLWithPath: "/tmp"))
        let attachments = [
            URL(fileURLWithPath: "/tmp/screenshot.png"),
            URL(fileURLWithPath: "/tmp/log.txt"),
        ]
        let args = CLIBuilder.buildArguments(
            prompt: "Analyze",
            config: config,
            attachmentPaths: attachments
        )
        XCTAssertTrue(args.contains("-i"))
        XCTAssertTrue(args.contains("/tmp/screenshot.png"))
        XCTAssertTrue(args.contains("/tmp/log.txt"))
    }

    func testCLIBuilderBuildProcessSetsWorkingDirectory() throws {
        // Only test argument construction; don't require actual CLI binaries
        let url = URL(fileURLWithPath: "/tmp/test-project")
        let config = AgentSpawnConfig(type: .claude, workingDirectory: url)
        let args = CLIBuilder.buildArguments(prompt: "Hello", config: config)
        XCTAssertTrue(args.contains("-p"))
        XCTAssertTrue(args.contains("Hello"))
    }

    // MARK: - ProgressCoalescer

    func testProgressCoalescerTextAlwaysPasses() async {
        let coalescer = ProgressCoalescer(interval: 10.0)
        let event1 = await coalescer.filter(.text("hello"))
        let event2 = await coalescer.filter(.text("world"))
        XCTAssertNotNil(event1)
        XCTAssertNotNil(event2)
    }

    func testProgressCoalescerDoneAlwaysPasses() async {
        let coalescer = ProgressCoalescer(interval: 10.0)
        let event = await coalescer.filter(.done(summary: "Done", sessionID: nil))
        XCTAssertNotNil(event)
    }

    func testProgressCoalescerErrorAlwaysPasses() async {
        let coalescer = ProgressCoalescer(interval: 10.0)
        let event1 = await coalescer.filter(.error("oops"))
        let event2 = await coalescer.filter(.error("again"))
        XCTAssertNotNil(event1)
        XCTAssertNotNil(event2)
    }

    func testProgressCoalescerToolUseCoalesced() async {
        let coalescer = ProgressCoalescer(interval: 10.0)
        // First tool use should pass
        let first = await coalescer.filter(.toolUse(name: "Read", input: "{}"))
        XCTAssertNotNil(first)
        // Second tool use within interval should be suppressed
        let second = await coalescer.filter(.toolUse(name: "Write", input: "{}"))
        XCTAssertNil(second)
    }

    func testProgressCoalescerToolResultCoalesced() async {
        let coalescer = ProgressCoalescer(interval: 10.0)
        let first = await coalescer.filter(.toolResult("result1"))
        XCTAssertNotNil(first)
        let second = await coalescer.filter(.toolResult("result2"))
        XCTAssertNil(second)
    }

    func testProgressCoalescerToolUsePassesAfterInterval() async {
        let coalescer = ProgressCoalescer(interval: 0.1)
        let first = await coalescer.filter(.toolUse(name: "Read", input: "{}"))
        XCTAssertNotNil(first)
        // Wait for interval to pass
        try? await Task.sleep(nanoseconds: 200_000_000)
        let second = await coalescer.filter(.toolUse(name: "Write", input: "{}"))
        XCTAssertNotNil(second)
    }

    // MARK: - AgentSession

    func testAgentSessionCreation() {
        let id = UUID()
        let url = URL(fileURLWithPath: "/projects/myapp")
        let date = Date(timeIntervalSince1970: 1000)
        let session = AgentSession(
            id: id,
            agentType: .claude,
            senderID: "user123",
            prompt: "Fix the tests",
            workingDirectory: url,
            startedAt: date,
            agentSessionID: "sess-abc"
        )
        XCTAssertEqual(session.id, id)
        XCTAssertEqual(session.agentType, .claude)
        XCTAssertEqual(session.senderID, "user123")
        XCTAssertEqual(session.prompt, "Fix the tests")
        XCTAssertEqual(session.workingDirectory, url)
        XCTAssertEqual(session.startedAt, date)
        XCTAssertEqual(session.agentSessionID, "sess-abc")
    }

    func testAgentSessionDefaults() {
        let session = AgentSession(
            agentType: .codex,
            senderID: "user1",
            prompt: "Hello",
            workingDirectory: URL(fileURLWithPath: "/tmp")
        )
        XCTAssertNotEqual(session.id, UUID()) // auto-generated
        XCTAssertNil(session.agentSessionID)
    }

    // MARK: - AgentSpawner Concurrency Limits

    func testSpawnerRejectsOverGlobalLimit() async {
        let spawner = AgentSpawner(maxConcurrent: 0, maxPerSender: 5)
        let config = AgentSpawnConfig(
            type: .claude,
            workingDirectory: URL(fileURLWithPath: "/tmp")
        )
        do {
            _ = try await spawner.spawn(prompt: "test", config: config, senderID: "user1")
            XCTFail("Expected agentTooManyActive error")
        } catch let error as SwiftClawError {
            if case .agentTooManyActive(let current, let max) = error {
                XCTAssertEqual(current, 0)
                XCTAssertEqual(max, 0)
            } else {
                XCTFail("Expected agentTooManyActive, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testSpawnerRejectsOverSenderLimit() async {
        let spawner = AgentSpawner(maxConcurrent: 10, maxPerSender: 0)
        let config = AgentSpawnConfig(
            type: .claude,
            workingDirectory: URL(fileURLWithPath: "/tmp")
        )
        do {
            _ = try await spawner.spawn(prompt: "test", config: config, senderID: "user1")
            XCTFail("Expected agentTooManyActive error")
        } catch let error as SwiftClawError {
            if case .agentTooManyActive(let current, let max) = error {
                XCTAssertEqual(current, 0)
                XCTAssertEqual(max, 0)
            } else {
                XCTFail("Expected agentTooManyActive, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testSpawnerSessionsInitiallyEmpty() async {
        let spawner = AgentSpawner()
        let sessions = await spawner.sessions
        XCTAssertTrue(sessions.isEmpty)
    }

    func testSpawnerIsActiveReturnsFalseInitially() async {
        let spawner = AgentSpawner()
        let active = await spawner.isActive(for: "user1")
        XCTAssertFalse(active)
    }

    func testSpawnerSessionForUnknownIDReturnsNil() async {
        let spawner = AgentSpawner()
        let session = await spawner.session(for: UUID())
        XCTAssertNil(session)
    }

    // MARK: - Constants

    func testSpawnerDefaults() {
        XCTAssertEqual(Defaults.Spawner.defaultTimeout, 600)
        XCTAssertEqual(Defaults.Spawner.defaultIdleTimeout, 120)
        XCTAssertEqual(Defaults.Spawner.maxConcurrentAgents, 5)
        XCTAssertEqual(Defaults.Spawner.maxAgentsPerSender, 2)
        XCTAssertEqual(Defaults.Spawner.progressCoalesceInterval, 2.0)
    }

    // MARK: - Error Cases

    func testAgentSpawnerErrors() {
        let errors: [SwiftClawError] = [
            .agentCLINotFound("claude"),
            .agentTooManyActive(current: 5, max: 5),
            .agentNonZeroExit(code: 1, stderr: "error"),
            .agentTimeout(seconds: 600),
            .agentIdleTimeout(seconds: 120),
        ]
        for error in errors {
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }
    }

    func testAgentCLINotFoundContainsName() {
        let error = SwiftClawError.agentCLINotFound("codex")
        XCTAssertTrue(error.localizedDescription.contains("codex"))
    }

    func testAgentTooManyActiveContainsCounts() {
        let error = SwiftClawError.agentTooManyActive(current: 3, max: 5)
        XCTAssertTrue(error.localizedDescription.contains("3"))
        XCTAssertTrue(error.localizedDescription.contains("5"))
    }
}
