import Foundation
import ChannelKit
import Shared
import ClawLogging

// MARK: - Configuration

public struct IMessageChannelConfiguration: Sendable, Codable, ChannelConfiguration {
    public var channelID: String = "imessage"
    public var isEnabled: Bool = true
    public var pollInterval: TimeInterval = 2.0
    public var dbPath: String?
    public var allowlist: [String]?

    public init(
        pollInterval: TimeInterval = 2.0,
        dbPath: String? = nil,
        allowlist: [String]? = nil
    ) {
        self.pollInterval = pollInterval
        self.dbPath = dbPath
        self.allowlist = allowlist
    }
}

// MARK: - iMessage Channel

/// Bidirectional iMessage channel on macOS.
/// Sends via AppleScript → Messages.app, receives by polling chat.db via GRDB.
public actor IMessageChannel: Channel {
    public let id = "imessage"
    public let displayName = "iMessage"

    public nonisolated var capabilities: ChannelCapabilities { .multimedia }
    public nonisolated var limits: ChannelLimits { .imessage }

    public private(set) var status: ChannelStatus = .disconnected
    private var messageHandler: (@Sendable (InboundMessage) async -> Void)?
    private var pollTask: Task<Void, Never>?
    private let config: IMessageChannelConfiguration
    private let logger = Log.channels

    #if os(macOS)
    private var chatDBReader: ChatDBReader?
    private var lastSeenRowID: Int64 = 0
    #endif

    public init(config: IMessageChannelConfiguration = .init()) {
        self.config = config
    }

    public func start() async throws {
        #if os(macOS)
        status = .connecting
        logger.info("iMessage channel starting (poll interval: \(config.pollInterval)s)")

        // Verify Messages.app is accessible
        guard try await runAppleScript("tell application \"Messages\" to return name") != nil else {
            status = .error("Messages.app not accessible")
            throw IRelayError.channelNotFound("Messages.app not accessible")
        }

        // Initialize chat.db reader
        let dbPath = config.dbPath ?? (NSHomeDirectory() + "/Library/Messages/chat.db")
        let reader = ChatDBReader(dbPath: dbPath)
        self.chatDBReader = reader

        // Load or initialize cursor
        if let saved = reader.loadLastSeenRowID() {
            lastSeenRowID = saved
            logger.info("Resumed iMessage cursor at ROWID \(saved)")
        } else {
            // First launch: skip existing history
            do {
                lastSeenRowID = try reader.currentMaxRowID()
                reader.saveLastSeenRowID(lastSeenRowID)
                logger.info("Initialized iMessage cursor at ROWID \(lastSeenRowID)")
            } catch {
                logger.warning("Could not read chat.db max ROWID: \(error). Starting from 0.")
                lastSeenRowID = 0
            }
        }

        status = .connected
        startPolling()
        logger.info("iMessage channel connected")
        #else
        throw IRelayError.platformUnsupported(feature: "iMessage requires macOS")
        #endif
    }

    public func stop() async throws {
        pollTask?.cancel()
        pollTask = nil
        status = .disconnected
        logger.info("iMessage channel stopped")
    }

    public func send(_ message: OutboundMessage) async throws {
        #if os(macOS)
        try IMessageSender.send(content: message.content, to: message.recipientID)
        logger.debug("Sent iMessage to \(message.recipientID)")
        #else
        throw IRelayError.platformUnsupported(feature: "iMessage requires macOS")
        #endif
    }

    public func onMessage(_ handler: @escaping @Sendable (InboundMessage) async -> Void) {
        self.messageHandler = handler
    }

    // MARK: - Polling

    private func startPolling() {
        let interval = config.pollInterval
        pollTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                await pollNewMessages()
            }
        }
    }

    private func pollNewMessages() async {
        #if os(macOS)
        guard let reader = chatDBReader else { return }

        do {
            let messages = try reader.fetchNewMessages(since: lastSeenRowID)

            for msg in messages {
                // Update cursor
                if msg.rowID > lastSeenRowID {
                    lastSeenRowID = msg.rowID
                }

                // Check allowlist
                if let allowlist = config.allowlist, !allowlist.isEmpty {
                    guard allowlist.contains(msg.senderID) else {
                        logger.debug("Skipping message from non-allowlisted sender: \(msg.senderID)")
                        continue
                    }
                }

                // Build message content
                let content = buildContent(from: msg)

                let inbound = InboundMessage(
                    channelID: id,
                    senderID: msg.senderID,
                    sessionKey: "imessage:\(msg.senderID)",
                    content: content,
                    timestamp: msg.timestamp
                )

                await messageHandler?(inbound)
            }

            // Persist cursor after processing batch
            if !messages.isEmpty {
                reader.saveLastSeenRowID(lastSeenRowID)
            }

        } catch {
            logger.warning("iMessage poll error: \(error)")
        }
        #endif
    }

    // MARK: - Content Building

    #if os(macOS)
    private func buildContent(from message: ParsedMessage) -> MessageContent {
        let hasText = message.text != nil && !message.text!.isEmpty
        let hasAttachments = !message.attachments.isEmpty

        if hasText && !hasAttachments {
            return .text(message.text!)
        }

        if !hasText && hasAttachments && message.attachments.count == 1 {
            let att = message.attachments[0]
            return contentForAttachment(att)
        }

        // Compound: text + attachments or multiple attachments
        var parts: [MessageContent] = []

        if let text = message.text, !text.isEmpty {
            parts.append(.text(text))
        }

        for att in message.attachments {
            parts.append(contentForAttachment(att))
        }

        if parts.count == 1 {
            return parts[0]
        }
        return .compound(parts)
    }

    private func contentForAttachment(_ att: ParsedAttachment) -> MessageContent {
        let mime = att.mimeType.lowercased()
        if mime.hasPrefix("image/") {
            return .image(att.data, mimeType: att.mimeType)
        } else if mime.hasPrefix("video/") {
            return .video(att.data, mimeType: att.mimeType)
        } else if mime.hasPrefix("audio/") {
            return .audio(att.data, mimeType: att.mimeType)
        } else {
            return .file(att.data, filename: att.filename, mimeType: att.mimeType)
        }
    }
    #endif

    // MARK: - AppleScript

    #if os(macOS)
    private func runAppleScript(_ source: String) async throws -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", source]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    #endif
}
