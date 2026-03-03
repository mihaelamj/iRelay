import Foundation
import ChannelKit
import Shared
import ClawLogging

// MARK: - Configuration

public struct IMessageChannelConfiguration: Sendable, Codable, ChannelConfiguration {
    public var channelID: String = "imessage"
    public var isEnabled: Bool = true
    public var pollInterval: TimeInterval = 5.0

    public init() {}
}

// MARK: - iMessage Channel

/// iMessage channel using AppleScript bridge on macOS.
/// Sends via `osascript` → Messages.app, polls for incoming.
public actor IMessageChannel: Channel {
    public let id = "imessage"
    public let displayName = "iMessage"
    public let maxTextLength = Defaults.TextLimits.iMessage

    public private(set) var status: ChannelStatus = .disconnected
    private var messageHandler: (@Sendable (InboundMessage) async -> Void)?
    private var pollTask: Task<Void, Never>?
    private let config: IMessageChannelConfiguration
    private let logger = Log.channels

    public init(config: IMessageChannelConfiguration = .init()) {
        self.config = config
    }

    public func start() async throws {
        #if os(macOS)
        status = .connecting
        logger.info("iMessage channel starting")

        // Verify Messages.app is accessible
        guard try await runAppleScript("tell application \"Messages\" to return name") != nil else {
            status = .error("Messages.app not accessible")
            throw SwiftClawError.channelNotFound("Messages.app not accessible")
        }

        status = .connected
        startPolling()
        logger.info("iMessage channel connected")
        #else
        throw SwiftClawError.platformUnsupported("iMessage requires macOS")
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
        guard let text = message.content.textValue else {
            throw SwiftClawError.channelSendFailed(channelID: id, reason: "Only text supported")
        }

        let escaped = text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let recipient = message.recipientID.replacingOccurrences(of: "\"", with: "\\\"")

        let script = """
            tell application "Messages"
                set targetBuddy to buddy "\(recipient)" of service 1
                send "\(escaped)" to targetBuddy
            end tell
            """

        guard try await runAppleScript(script) != nil else {
            throw SwiftClawError.channelSendFailed(channelID: id, reason: "AppleScript failed")
        }
        logger.debug("Sent iMessage to \(message.recipientID)")
        #else
        throw SwiftClawError.platformUnsupported("iMessage requires macOS")
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
        // MVP: poll ~/Library/Messages/chat.db for new rows
        // Full implementation reads from SQLite directly
    }

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
