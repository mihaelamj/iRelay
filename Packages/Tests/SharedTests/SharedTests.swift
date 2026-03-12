import XCTest
@testable import Shared

final class SharedTests: XCTestCase {

    // MARK: - Version

    func testVersion() {
        XCTAssertEqual(IRelayVersion.current, "0.1.0")
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
        let msg = ChatMessage(role: .user, text: "Hello AI", metadata: ["key": "val"])
        XCTAssertEqual(msg.role, .user)
        XCTAssertEqual(msg.textContent, "Hello AI")
        XCTAssertEqual(msg.metadata?["key"], "val")
    }

    func testChatRoleRawValues() {
        XCTAssertEqual(ChatRole.system.rawValue, "system")
        XCTAssertEqual(ChatRole.user.rawValue, "user")
        XCTAssertEqual(ChatRole.assistant.rawValue, "assistant")
        XCTAssertEqual(ChatRole.tool.rawValue, "tool")
    }

    func testChatMessageCodable() throws {
        let original = ChatMessage(role: .assistant, text: "Response",
                                   timestamp: Date(timeIntervalSince1970: 3000), metadata: ["s": "t"])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ChatMessage.self, from: data)
        XCTAssertEqual(decoded.role, .assistant)
        XCTAssertEqual(decoded.textContent, "Response")
        XCTAssertEqual(decoded.metadata?["s"], "t")
    }

    func testChatMessageCodableWithoutMetadata() throws {
        let original = ChatMessage(role: .system, text: "Prompt")
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
        let errors: [IRelayError] = [
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
            .agentCLINotFound("t"),
            .agentTooManyActive(current: 1, max: 5),
            .agentNonZeroExit(code: 1, stderr: "err"),
            .agentTimeout(seconds: 60),
            .agentIdleTimeout(seconds: 30),
            .chunkingFailed("t"), .timeout(operation: "o", seconds: 1),
            .platformUnsupported(feature: "f"),
        ]
        XCTAssertEqual(errors.count, 30)
        for error in errors {
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }
    }

    func testErrorContainsContext() {
        XCTAssertTrue(IRelayError.channelNotFound("telegram").localizedDescription.contains("telegram"))
        XCTAssertTrue(IRelayError.timeout(operation: "fetch", seconds: 30).localizedDescription.contains("fetch"))
    }

    // MARK: - Paths

    func testIRelayPathsNotEmpty() {
        XCTAssertFalse(IRelayPaths.configDirectory.path.isEmpty)
        XCTAssertFalse(IRelayPaths.dataDirectory.path.isEmpty)
        XCTAssertTrue(IRelayPaths.configFile.path.contains("config"))
        XCTAssertTrue(IRelayPaths.databaseFile.path.contains("irelay"))
    }

    func testAgentDirectory() {
        let dir = IRelayPaths.agentDirectory(agentID: "test-agent")
        XCTAssertTrue(dir.path.contains("test-agent"))
        XCTAssertTrue(dir.path.contains("agents"))
    }

    func testEnsureDirectoryExists() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("irelay-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }
        try IRelayPaths.ensureDirectoryExists(tmpDir)
        var isDir: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: tmpDir.path, isDirectory: &isDir))
        XCTAssertTrue(isDir.boolValue)
    }

    // MARK: - Configuration

    func testConfigDefaults() {
        let config = IRelayConfig()
        XCTAssertEqual(config.gateway.host, "127.0.0.1")
        XCTAssertEqual(config.gateway.port, 18789)
        XCTAssertNil(config.gateway.authToken)
        XCTAssertTrue(config.agents.agents.isEmpty)
        XCTAssertTrue(config.channels.enabled.isEmpty)
        XCTAssertTrue(config.providers.providers.isEmpty)
    }

    func testConfigCodable() throws {
        let config = IRelayConfig(
            gateway: GatewayConfig(host: "0.0.0.0", port: 9999, authToken: "tok"),
            agents: AgentsConfig(agents: [AgentDefinition(id: "main", name: "Main")]),
            channels: ChannelsConfig(enabled: ["tg": ChannelEntry(isEnabled: true)]),
            providers: ProvidersConfig(providers: ["claude": ProviderEntry(isEnabled: true)])
        )
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(IRelayConfig.self, from: data)
        XCTAssertEqual(decoded.gateway.port, 9999)
        XCTAssertEqual(decoded.agents.agents.count, 1)
        XCTAssertTrue(decoded.channels.enabled["tg"]?.isEnabled ?? false)
    }

    func testConfigSaveAndLoad() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-config-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let config = IRelayConfig(gateway: GatewayConfig(host: "localhost", port: 8080))
        try config.save(to: url)
        let loaded = try IRelayConfig.load(from: url)
        XCTAssertEqual(loaded.gateway.host, "localhost")
        XCTAssertEqual(loaded.gateway.port, 8080)
    }

    func testConfigLoadNonexistentReturnsDefault() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("nonexistent-\(UUID().uuidString).json")
        let config = try IRelayConfig.load(from: url)
        XCTAssertEqual(config.gateway.port, Defaults.gatewayPort)
    }

    // MARK: - ContentBlock

    func testContentBlockText() {
        let block = ContentBlock.text("hello")
        XCTAssertEqual(block.textValue, "hello")
    }

    func testContentBlockImageHasNoTextValue() {
        let source = ImageSource(url: "https://example.com/img.png", mediaType: "image/png")
        let block = ContentBlock.image(source)
        XCTAssertNil(block.textValue)
    }

    func testContentBlockToolUse() {
        let block = ContentBlock.toolUse(id: "t1", name: "read_file", input: "{\"path\":\"/tmp\"}")
        if case .toolUse(let id, let name, let input) = block {
            XCTAssertEqual(id, "t1")
            XCTAssertEqual(name, "read_file")
            XCTAssertTrue(input.contains("/tmp"))
        } else { XCTFail("Expected .toolUse") }
    }

    func testContentBlockToolResult() {
        let block = ContentBlock.toolResult(toolUseID: "t1", content: "done", isError: false)
        if case .toolResult(let id, let content, let isError) = block {
            XCTAssertEqual(id, "t1")
            XCTAssertEqual(content, "done")
            XCTAssertFalse(isError)
        } else { XCTFail("Expected .toolResult") }
    }

    func testContentBlockEquatable() {
        XCTAssertEqual(ContentBlock.text("a"), ContentBlock.text("a"))
        XCTAssertNotEqual(ContentBlock.text("a"), ContentBlock.text("b"))
    }

    func testContentBlockTextCodable() throws {
        let original = ContentBlock.text("Hello world")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ContentBlock.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testContentBlockImageCodable() throws {
        let source = ImageSource(data: Data([0x89, 0x50]), mediaType: "image/png")
        let original = ContentBlock.image(source)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ContentBlock.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testContentBlockToolUseCodable() throws {
        let original = ContentBlock.toolUse(id: "tu1", name: "bash", input: "{}")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ContentBlock.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testContentBlockToolResultCodable() throws {
        let original = ContentBlock.toolResult(toolUseID: "tu1", content: "error", isError: true)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ContentBlock.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testContentBlockUnknownTypeDecodesToText() throws {
        let json = #"{"type":"unknown","text":"fallback"}"#
        let decoded = try JSONDecoder().decode(ContentBlock.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(decoded, .text("fallback"))
    }

    // MARK: - ImageSource

    func testImageSourceBase64Init() {
        let raw = Data([0x89, 0x50, 0x4E, 0x47])
        let source = ImageSource(data: raw, mediaType: "image/png")
        XCTAssertEqual(source.type, .base64)
        XCTAssertEqual(source.mediaType, "image/png")
        XCTAssertEqual(source.data, raw.base64EncodedString())
    }

    func testImageSourceURLInit() {
        let source = ImageSource(url: "https://example.com/img.jpg", mediaType: "image/jpeg")
        XCTAssertEqual(source.type, .url)
        XCTAssertEqual(source.mediaType, "image/jpeg")
        XCTAssertEqual(source.data, "https://example.com/img.jpg")
    }

    func testImageSourceCodable() throws {
        let original = ImageSource(url: "https://example.com/a.png", mediaType: "image/png")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ImageSource.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testImageSourceTypeRawValues() {
        XCTAssertEqual(ImageSourceType.base64.rawValue, "base64")
        XCTAssertEqual(ImageSourceType.url.rawValue, "url")
    }

    // MARK: - MessageContent (expanded)

    func testMessageContentVideo() {
        let content = MessageContent.video(Data([0x00]), mimeType: "video/mp4")
        XCTAssertTrue(content.isMedia)
        XCTAssertFalse(content.isText)
        XCTAssertNil(content.textValue)
    }

    func testMessageContentLink() {
        let url = URL(string: "https://example.com")!
        let content = MessageContent.link(url, title: "Example")
        XCTAssertFalse(content.isText)
        XCTAssertFalse(content.isMedia)
        XCTAssertNil(content.textValue)
    }

    func testMessageContentCompound() {
        let content = MessageContent.compound([.text("caption"), .image(Data([1]), mimeType: "image/png")])
        XCTAssertFalse(content.isText)
        XCTAssertFalse(content.isMedia)
    }

    func testMessageContentIsMedia() {
        XCTAssertTrue(MessageContent.image(Data(), mimeType: "image/png").isMedia)
        XCTAssertTrue(MessageContent.video(Data(), mimeType: "video/mp4").isMedia)
        XCTAssertTrue(MessageContent.audio(Data(), mimeType: "audio/mp3").isMedia)
        XCTAssertTrue(MessageContent.file(Data(), filename: "f", mimeType: "text/plain").isMedia)
        XCTAssertFalse(MessageContent.text("hi").isMedia)
        XCTAssertFalse(MessageContent.link(URL(string: "https://x.com")!, title: nil).isMedia)
        XCTAssertFalse(MessageContent.location(latitude: 0, longitude: 0).isMedia)
    }

    func testTextFallbackText() {
        XCTAssertEqual(MessageContent.text("hello").textFallback, "hello")
    }

    func testTextFallbackImage() {
        let fb = MessageContent.image(Data(), mimeType: "image/png").textFallback
        XCTAssertEqual(fb, "[Image: image/png]")
    }

    func testTextFallbackVideo() {
        let fb = MessageContent.video(Data(), mimeType: "video/mp4").textFallback
        XCTAssertEqual(fb, "[Video: video/mp4]")
    }

    func testTextFallbackAudio() {
        let fb = MessageContent.audio(Data(), mimeType: "audio/mp3").textFallback
        XCTAssertEqual(fb, "[Audio: audio/mp3]")
    }

    func testTextFallbackFile() {
        let fb = MessageContent.file(Data(), filename: "doc.pdf", mimeType: "application/pdf").textFallback
        XCTAssertEqual(fb, "[File: doc.pdf]")
    }

    func testTextFallbackLinkWithTitle() {
        let url = URL(string: "https://example.com")!
        let fb = MessageContent.link(url, title: "Example").textFallback
        XCTAssertEqual(fb, "Example: https://example.com")
    }

    func testTextFallbackLinkWithoutTitle() {
        let url = URL(string: "https://example.com")!
        let fb = MessageContent.link(url, title: nil).textFallback
        XCTAssertEqual(fb, "https://example.com")
    }

    func testTextFallbackLocation() {
        let fb = MessageContent.location(latitude: 45.8, longitude: 15.97).textFallback
        XCTAssertTrue(fb.contains("45.8"))
        XCTAssertTrue(fb.contains("15.97"))
    }

    func testTextFallbackCompound() {
        let content = MessageContent.compound([
            .text("Look at this:"),
            .image(Data(), mimeType: "image/jpeg"),
        ])
        let fb = content.textFallback
        XCTAssertTrue(fb.contains("Look at this:"))
        XCTAssertTrue(fb.contains("[Image: image/jpeg]"))
    }

    // MARK: - ChatMessage (multimodal)

    func testChatMessageMultimodalContent() {
        let source = ImageSource(url: "https://example.com/img.png", mediaType: "image/png")
        let msg = ChatMessage(role: .user, content: [
            .text("What is this?"),
            .image(source),
        ])
        XCTAssertEqual(msg.content.count, 2)
        XCTAssertEqual(msg.textContent, "What is this?")
    }

    func testChatMessageTextConvenienceInit() {
        let msg = ChatMessage(role: .assistant, text: "Hello")
        XCTAssertEqual(msg.content.count, 1)
        XCTAssertEqual(msg.content.first, .text("Hello"))
        XCTAssertEqual(msg.textContent, "Hello")
    }

    func testChatMessageTextContentConcatenation() {
        let msg = ChatMessage(role: .user, content: [
            .text("Part 1"),
            .text(" Part 2"),
        ])
        XCTAssertEqual(msg.textContent, "Part 1 Part 2")
    }

    func testChatMessageMultimodalCodable() throws {
        let source = ImageSource(data: Data([0xFF, 0xD8]), mediaType: "image/jpeg")
        let original = ChatMessage(role: .user, content: [
            .text("Describe this image"),
            .image(source),
        ], timestamp: Date(timeIntervalSince1970: 5000))
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ChatMessage.self, from: data)
        XCTAssertEqual(decoded.content.count, 2)
        XCTAssertEqual(decoded.textContent, "Describe this image")
        XCTAssertEqual(decoded.role, .user)
    }

    // MARK: - OutboundMessage.with(content:)

    func testOutboundMessageWithContent() {
        let original = OutboundMessage(
            sessionID: "s1", channelID: "imsg", recipientID: "u1",
            content: .text("original"), replyTo: "msg-1"
        )
        let modified = original.with(content: .image(Data([1]), mimeType: "image/png"))
        XCTAssertEqual(modified.sessionID, "s1")
        XCTAssertEqual(modified.channelID, "imsg")
        XCTAssertEqual(modified.recipientID, "u1")
        XCTAssertEqual(modified.replyTo, "msg-1")
        XCTAssertTrue(modified.content.isMedia)
    }
}
