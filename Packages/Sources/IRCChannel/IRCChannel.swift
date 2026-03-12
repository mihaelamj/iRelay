import Foundation
import ChannelKit
import Shared
import IRelayLogging
#if canImport(Network)
import Network
#endif

// MARK: - Configuration

public struct IRCChannelConfiguration: Sendable, Codable, ChannelConfiguration {
    public var channelID: String = "irc"
    public var isEnabled: Bool = true
    public var server: String
    public var port: Int
    public var nickname: String
    public var channels: [String]
    public var useTLS: Bool

    public init(server: String, port: Int = 6667, nickname: String, channels: [String], useTLS: Bool = false) {
        self.server = server
        self.port = port
        self.nickname = nickname
        self.channels = channels
        self.useTLS = useTLS
    }
}

// MARK: - IRC Channel

/// IRC channel using raw TCP via NWConnection (macOS/iOS) or Foundation sockets.
public actor IRCChannel: Channel {
    public let id = "irc"
    public let displayName = "IRC"
    public let maxTextLength = Defaults.TextLimits.irc

    public private(set) var status: ChannelStatus = .disconnected
    private var messageHandler: (@Sendable (InboundMessage) async -> Void)?
    private let config: IRCChannelConfiguration
    private let logger = Log.channels
    private var readTask: Task<Void, Never>?
    private var inputStream: InputStream?
    private var outputStream: OutputStream?

    public init(config: IRCChannelConfiguration) {
        self.config = config
    }

    public func start() async throws {
        status = .connecting
        logger.info("IRC connecting to \(config.server):\(config.port)")

        var inStream: InputStream?
        var outStream: OutputStream?
        Stream.getStreamsToHost(
            withName: config.server,
            port: config.port,
            inputStream: &inStream,
            outputStream: &outStream
        )

        guard let input = inStream, let output = outStream else {
            status = .error("Failed to create streams")
            throw IRelayError.connectionFailed("Cannot connect to \(config.server):\(config.port)")
        }

        input.open()
        output.open()
        self.inputStream = input
        self.outputStream = output

        // Send IRC registration
        try sendRaw("NICK \(config.nickname)")
        try sendRaw("USER \(config.nickname) 0 * :iRelay Bot")

        // Join channels
        for channel in config.channels {
            try sendRaw("JOIN \(channel)")
        }

        status = .connected
        startReadLoop()
        logger.info("IRC connected as \(config.nickname)")
    }

    public func stop() async throws {
        readTask?.cancel()
        readTask = nil
        try? sendRaw("QUIT :iRelay shutting down")
        inputStream?.close()
        outputStream?.close()
        inputStream = nil
        outputStream = nil
        status = .disconnected
        logger.info("IRC disconnected")
    }

    public func send(_ message: OutboundMessage) async throws {
        guard let text = message.content.textValue else {
            throw IRelayError.channelSendFailed(channelID: id, reason: "Only text supported")
        }
        // Chunk for IRC 512-byte limit
        let maxMsg = maxTextLength - message.recipientID.count - 12 // PRIVMSG + overhead
        let chunks = stride(from: 0, to: text.count, by: maxMsg).map { start in
            let begin = text.index(text.startIndex, offsetBy: start)
            let end = text.index(begin, offsetBy: min(maxMsg, text.count - start))
            return String(text[begin..<end])
        }
        for chunk in chunks {
            try sendRaw("PRIVMSG \(message.recipientID) :\(chunk)")
        }
    }

    public func onMessage(_ handler: @escaping @Sendable (InboundMessage) async -> Void) {
        self.messageHandler = handler
    }

    // MARK: - Raw IRC

    private func sendRaw(_ line: String) throws {
        guard let output = outputStream else {
            throw IRelayError.channelDisconnected("irc")
        }
        let data = Data("\(line)\r\n".utf8)
        data.withUnsafeBytes { ptr in
            guard let base = ptr.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
            output.write(base, maxLength: data.count)
        }
    }

    private func startReadLoop() {
        readTask = Task {
            guard let input = inputStream else { return }
            let bufferSize = 4096
            var buffer = [UInt8](repeating: 0, count: bufferSize)
            var partial = ""

            while !Task.isCancelled && input.hasBytesAvailable {
                let bytesRead = input.read(&buffer, maxLength: bufferSize)
                guard bytesRead > 0 else {
                    try? await Task.sleep(for: .milliseconds(100))
                    continue
                }

                partial += String(bytes: buffer[0..<bytesRead], encoding: .utf8) ?? ""
                let lines = partial.components(separatedBy: "\r\n")
                partial = lines.last ?? ""

                for line in lines.dropLast() where !line.isEmpty {
                    await handleLine(line)
                }
            }
        }
    }

    private func handleLine(_ line: String) async {
        // Respond to PING
        if line.hasPrefix("PING") {
            let token = String(line.dropFirst(5))
            try? sendRaw("PONG \(token)")
            return
        }

        // Parse PRIVMSG: :nick!user@host PRIVMSG #channel :message
        guard line.contains("PRIVMSG") else { return }
        let parts = line.components(separatedBy: " ")
        guard parts.count >= 4 else { return }

        let sender = String(parts[0].dropFirst()).components(separatedBy: "!").first ?? "unknown"
        let target = parts[2]
        let message = parts[3...].joined(separator: " ")
        let text = message.hasPrefix(":") ? String(message.dropFirst()) : message

        let inbound = InboundMessage(
            channelID: id,
            senderID: sender,
            sessionKey: "irc:\(target):\(sender)",
            content: .text(text)
        )
        await messageHandler?(inbound)
    }
}
