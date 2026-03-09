import Foundation
import ChannelKit
import Shared
import ClawLogging

// MARK: - Configuration

public struct SignalChannelConfiguration: Sendable, Codable, ChannelConfiguration {
    public var channelID: String = "signal"
    public var isEnabled: Bool = true
    public var phoneNumber: String
    public var signalCliPath: String

    public init(phoneNumber: String, signalCliPath: String = "/usr/local/bin/signal-cli") {
        self.phoneNumber = phoneNumber
        self.signalCliPath = signalCliPath
    }
}

// MARK: - Signal Channel

/// Signal channel using signal-cli as a subprocess.
/// Sends via `signal-cli send`, receives via `signal-cli receive --json`.
public actor SignalChannel: Channel {
    public let id = "signal"
    public let displayName = "Signal"
    public let maxTextLength = Defaults.TextLimits.default

    public private(set) var status: ChannelStatus = .disconnected
    private var messageHandler: (@Sendable (InboundMessage) async -> Void)?
    private var receiveTask: Task<Void, Never>?
    private let config: SignalChannelConfiguration
    private let logger = Log.channels

    public init(config: SignalChannelConfiguration) {
        self.config = config
    }

    public func start() async throws {
        status = .connecting
        logger.info("Signal channel starting (phone: \(config.phoneNumber))")

        // Verify signal-cli exists
        guard FileManager.default.fileExists(atPath: config.signalCliPath) else {
            status = .error("signal-cli not found")
            throw IRelayError.channelNotFound("signal-cli not found at \(config.signalCliPath)")
        }

        status = .connected
        startReceiveLoop()
        logger.info("Signal channel connected")
    }

    public func stop() async throws {
        receiveTask?.cancel()
        receiveTask = nil
        status = .disconnected
        logger.info("Signal channel stopped")
    }

    public func send(_ message: OutboundMessage) async throws {
        guard let text = message.content.textValue else {
            throw IRelayError.channelSendFailed(channelID: id, reason: "Only text supported")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: config.signalCliPath)
        process.arguments = [
            "-a", config.phoneNumber,
            "send", "-m", text,
            message.recipientID,
        ]
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw IRelayError.channelSendFailed(channelID: id, reason: "signal-cli exit \(process.terminationStatus)")
        }
        logger.debug("Signal message sent to \(message.recipientID)")
    }

    public func onMessage(_ handler: @escaping @Sendable (InboundMessage) async -> Void) {
        self.messageHandler = handler
    }

    // MARK: - Receive Loop

    private func startReceiveLoop() {
        let cliPath = config.signalCliPath
        let phone = config.phoneNumber
        receiveTask = Task {
            while !Task.isCancelled {
                do {
                    let output = try await runCli(cliPath, args: ["-a", phone, "receive", "--json", "--timeout", "10"])
                    for line in output.components(separatedBy: "\n") where !line.isEmpty {
                        guard let data = line.data(using: .utf8),
                              let envelope = try? JSONDecoder().decode(SignalEnvelope.self, from: data),
                              let dataMsg = envelope.envelope.dataMessage,
                              let body = dataMsg.message else { continue }

                        let inbound = InboundMessage(
                            channelID: "signal",
                            senderID: envelope.envelope.source ?? "unknown",
                            sessionKey: "signal:\(envelope.envelope.source ?? "unknown")",
                            content: .text(body)
                        )
                        await messageHandler?(inbound)
                    }
                } catch {
                    if !Task.isCancelled {
                        try? await Task.sleep(for: .seconds(5))
                    }
                }
            }
        }
    }

    private func runCli(_ path: String, args: [String]) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}

// MARK: - Signal Types

private struct SignalEnvelope: Decodable {
    let envelope: Envelope
    struct Envelope: Decodable {
        let source: String?
        let dataMessage: DataMessage?
    }
    struct DataMessage: Decodable {
        let message: String?
        let timestamp: Int?
    }
}
