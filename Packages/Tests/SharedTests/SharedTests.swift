import XCTest
@testable import Shared

final class SharedTests: XCTestCase {

    // MARK: - Version

    func testVersion() {
        XCTAssertEqual(SwiftClawVersion.current, "0.1.0")
    }

    // MARK: - MessageContent

    func testMessageContentText() {
        let content = MessageContent.text("hello")
        XCTAssertTrue(content.isText)
        XCTAssertEqual(content.textValue, "hello")
    }

    func testMessageContentNonTextHasNoTextValue() {
        let content = MessageContent.image(Data([0x89]), mimeType: "image/png")
        XCTAssertFalse(content.isText)
        XCTAssertNil(content.textValue)
    }

    func testMessageContentImage() {
        let data = Data([0x89, 0x50])
        if case .image(let d, let mime) = MessageContent.image(data, mimeType: "image/png") {
            XCTAssertEqual(d, data)
            XCTAssertEqual(mime, "image/png")
        } else { XCTFail("Expected .image") }
    }

    func testMessageContentAudio() {
        if case .audio(let d, let mime) = MessageContent.audio(Data([0x01]), mimeType: "audio/mp3") {
            XCTAssertEqual(d.count, 1)
            XCTAssertEqual(mime, "audio/mp3")
        } else { XCTFail("Expected .audio") }
    }

    func testMessageContentFile() {
        if case .file(let d, let f, let mime) = MessageContent.file(Data([1, 2]), filename: "test.txt", mimeType: "text/plain") {
            XCTAssertEqual(d.count, 2)
            XCTAssertEqual(f, "test.txt")
            XCTAssertEqual(mime, "text/plain")
        } else { XCTFail("Expected .file") }
    }

    func testMessageContentLocation() {
        if case .location(let lat, let lon) = MessageContent.location(latitude: 45.8, longitude: 15.97) {
            XCTAssertEqual(lat, 45.8, accuracy: 0.001)
            XCTAssertEqual(lon, 15.97, accuracy: 0.001)
        } else { XCTFail("Expected .location") }
    }

    // MARK: - InboundMessage

    func testInboundMessageCreation() {
        let msg = InboundMessage(channelID: "telegram", senderID: "user123", sessionKey: "sess-1",
                                 content: .text("hello"), timestamp: Date(timeIntervalSince1970: 1000))
        XCTAssertEqual(msg.channelID, "telegram")
        XCTAssertEqual(msg.senderID, "user123")
        XCTAssertEqual(msg.sessionKey, "sess-1")
        XCTAssertNil(msg.replyTo)
    }

    func testInboundMessageDefaults() {
        let msg = InboundMessage(channelID: "slack", senderID: "u1", content: .text("hi"))
        XCTAssertNil(msg.sessionKey)
        XCTAssertNil(msg.replyTo)
    }

    // MARK: - OutboundMessage

    func testOutboundMessageCreation() {
        let msg = OutboundMessage(sessionID: "s1", channelID: "telegram", recipientID: "u1",
                                  content: .text("hi"), replyTo: "msg-1")
        XCTAssertEqual(msg.sessionID, "s1")
        XCTAssertEqual(msg.replyTo, "msg-1")
    }

    func testOutboundMessageDefaultReplyTo() {
        let msg = OutboundMessage(sessionID: "s", channelID: "c", recipientID: "r", content: .text("x"))
        XCTAssertNil(msg.replyTo)
    }

    // MARK: - ChatMessage

    func testChatMessageCreation() {
        let msg = ChatMessage(role: .user, content: "Hello AI", metadata: ["key": "val"])
        XCTAssertEqual(msg.role, .user)
        XCTAssertEqual(msg.content, "Hello AI")
        XCTAssertEqual(msg.metadata?["key"], "val")
    }

    func testChatRoleRawValues() {
        XCTAssertEqual(ChatRole.system.rawValue, "system")
        XCTAssertEqual(ChatRole.user.rawValue, "user")
        XCTAssertEqual(ChatRole.assistant.rawValue, "assistant")
        XCTAssertEqual(ChatRole.tool.rawValue, "tool")
    }

    func testChatMessageCodable() throws {
        let original = ChatMessage(role: .assistant, content: "Response",
                                   timestamp: Date(timeIntervalSince1970: 3000), metadata: ["s": "t"])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ChatMessage.self, from: data)
        XCTAssertEqual(decoded.role, .assistant)
        XCTAssertEqual(decoded.content, "Response")
        XCTAssertEqual(decoded.metadata?["s"], "t")
    }

    func testChatMessageCodableWithoutMetadata() throws {
        let original = ChatMessage(role: .system, content: "Prompt")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ChatMessage.self, from: data)
        XCTAssertEqual(decoded.role, .system)
    }

    // MARK: - ThinkingLevel

    func testThinkingLevelCaseIterable() {
        XCTAssertEqual(ThinkingLevel.allCases.count, 6)
    }

    func testThinkingLevelRawValues() {
        XCTAssertEqual(ThinkingLevel.off.rawValue, "off")
        XCTAssertEqual(ThinkingLevel.xhigh.rawValue, "xhigh")
    }

    func testThinkingLevelCodable() throws {
        let data = try JSONEncoder().encode(ThinkingLevel.high)
        let decoded = try JSONDecoder().decode(ThinkingLevel.self, from: data)
        XCTAssertEqual(decoded, .high)
    }

    // MARK: - SessionMetadata

    func testSessionMetadataDefaults() {
        let meta = SessionMetadata(channelID: "telegram", peerID: "user1")
        XCTAssertEqual(meta.agentID, Defaults.defaultAgentID)
        XCTAssertEqual(meta.thinkingLevel, .medium)
        XCTAssertNil(meta.modelOverride)
    }

    func testSessionMetadataCodable() throws {
        let original = SessionMetadata(agentID: "test", channelID: "slack", peerID: "p1",
                                       modelOverride: "opus", thinkingLevel: .high,
                                       createdAt: Date(timeIntervalSince1970: 1000),
                                       lastActiveAt: Date(timeIntervalSince1970: 2000))
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SessionMetadata.self, from: data)
        XCTAssertEqual(decoded.agentID, "test")
        XCTAssertEqual(decoded.modelOverride, "opus")
        XCTAssertEqual(decoded.thinkingLevel, .high)
    }

    // MARK: - Constants

    func testDefaultConstants() {
        XCTAssertEqual(Defaults.gatewayPort, 18789)
        XCTAssertEqual(Defaults.gatewayHost, "127.0.0.1")
        XCTAssertEqual(Defaults.sessionTimeoutSeconds, 3600)
        XCTAssertEqual(Defaults.connectionHeartbeatSeconds, 30)
        XCTAssertEqual(Defaults.requestTimeoutSeconds, 300)
        XCTAssertEqual(Defaults.maxMessageHistoryTokens, 100_000)
        XCTAssertEqual(Defaults.maxSessionAge, 86400 * 30)
        XCTAssertEqual(Defaults.defaultAgentID, "main")
    }

    func testTextLimits() {
        XCTAssertEqual(Defaults.TextLimits.telegram, 4000)
        XCTAssertEqual(Defaults.TextLimits.discord, 2000)
        XCTAssertEqual(Defaults.TextLimits.irc, 512)
        XCTAssertEqual(Defaults.TextLimits.iMessage, 20000)
        XCTAssertEqual(Defaults.TextLimits.`default`, 4000)
    }

    // MARK: - Errors

    func testAllErrorCasesHaveDescriptions() {
        let errors: [SwiftClawError] = [
            .connectionFailed("t"), .authenticationFailed("t"), .protocolError("t"),
            .channelNotFound("t"), .channelDisconnected("t"),
            .channelSendFailed(channelID: "c", reason: "r"),
            .messageNormalizationFailed("t"), .providerNotFound("t"),
            .providerAuthFailed(providerID: "p", reason: "r"),
            .modelNotFound(providerID: "p", modelID: "m"),
            .streamingFailed("t"), .toolCallFailed(toolName: "t", reason: "r"),
            .sessionNotFound("t"), .sessionExpired("t"),
            .agentNotFound("t"), .agentRoutingFailed("t"),
            .databaseError("t"), .migrationFailed(version: 1, reason: "r"),
            .configLoadFailed(path: "/", reason: "r"),
            .configInvalid(key: "k", reason: "r"),
            .secretNotFound("t"), .deliveryFailed(channelID: "c", reason: "r"),
            .chunkingFailed("t"), .timeout(operation: "o", seconds: 1),
            .platformUnsupported(feature: "f"),
        ]
        XCTAssertEqual(errors.count, 25)
        for error in errors {
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }
    }

    func testErrorContainsContext() {
        XCTAssertTrue(SwiftClawError.channelNotFound("telegram").localizedDescription.contains("telegram"))
        XCTAssertTrue(SwiftClawError.timeout(operation: "fetch", seconds: 30).localizedDescription.contains("fetch"))
    }

    // MARK: - Paths

    func testClawPathsNotEmpty() {
        XCTAssertFalse(ClawPaths.configDirectory.path.isEmpty)
        XCTAssertFalse(ClawPaths.dataDirectory.path.isEmpty)
        XCTAssertTrue(ClawPaths.configFile.path.contains("config"))
        XCTAssertTrue(ClawPaths.databaseFile.path.contains("swiftclaw"))
    }

    func testAgentDirectory() {
        let dir = ClawPaths.agentDirectory(agentID: "test-agent")
        XCTAssertTrue(dir.path.contains("test-agent"))
        XCTAssertTrue(dir.path.contains("agents"))
    }

    func testEnsureDirectoryExists() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftclaw-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }
        try ClawPaths.ensureDirectoryExists(tmpDir)
        var isDir: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: tmpDir.path, isDirectory: &isDir))
        XCTAssertTrue(isDir.boolValue)
    }

    // MARK: - Configuration

    func testConfigDefaults() {
        let config = SwiftClawConfig()
        XCTAssertEqual(config.gateway.host, "127.0.0.1")
        XCTAssertEqual(config.gateway.port, 18789)
        XCTAssertNil(config.gateway.authToken)
        XCTAssertTrue(config.agents.agents.isEmpty)
        XCTAssertTrue(config.channels.enabled.isEmpty)
        XCTAssertTrue(config.providers.providers.isEmpty)
    }

    func testConfigCodable() throws {
        let config = SwiftClawConfig(
            gateway: GatewayConfig(host: "0.0.0.0", port: 9999, authToken: "tok"),
            agents: AgentsConfig(agents: [AgentDefinition(id: "main", name: "Main")]),
            channels: ChannelsConfig(enabled: ["tg": ChannelEntry(isEnabled: true)]),
            providers: ProvidersConfig(providers: ["claude": ProviderEntry(isEnabled: true)])
        )
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(SwiftClawConfig.self, from: data)
        XCTAssertEqual(decoded.gateway.port, 9999)
        XCTAssertEqual(decoded.agents.agents.count, 1)
        XCTAssertTrue(decoded.channels.enabled["tg"]?.isEnabled ?? false)
    }

    func testConfigSaveAndLoad() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-config-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let config = SwiftClawConfig(gateway: GatewayConfig(host: "localhost", port: 8080))
        try config.save(to: url)
        let loaded = try SwiftClawConfig.load(from: url)
        XCTAssertEqual(loaded.gateway.host, "localhost")
        XCTAssertEqual(loaded.gateway.port, 8080)
    }

    func testConfigLoadNonexistentReturnsDefault() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("nonexistent-\(UUID().uuidString).json")
        let config = try SwiftClawConfig.load(from: url)
        XCTAssertEqual(config.gateway.port, Defaults.gatewayPort)
    }
}
