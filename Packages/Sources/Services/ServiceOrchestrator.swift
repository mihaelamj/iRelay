import Foundation
import Sessions
import Agents
import ChannelKit
import ProviderKit
import Shared
import ClawLogging

// MARK: - Service Orchestrator

/// The central orchestrator that wires channels → sessions → agents → delivery.
public actor ServiceOrchestrator {
    private let sessionManager: SessionManager
    private let agentRouter: AgentRouter
    private let channelRegistry: ChannelRegistry
    private let logger = Log.logger(for: "orchestrator")

    public init(
        sessionManager: SessionManager,
        agentRouter: AgentRouter,
        channelRegistry: ChannelRegistry
    ) {
        self.sessionManager = sessionManager
        self.agentRouter = agentRouter
        self.channelRegistry = channelRegistry
    }

    // MARK: - Bootstrap

    /// Wire up all channels to route inbound messages through the pipeline.
    public func start() async throws {
        let channels = await channelRegistry.all
        for channel in channels {
            let channelID = await channel.id
            await channel.onMessage { [weak self] inbound in
                guard let self else { return }
                await self.handleInbound(inbound)
            }
            logger.info("Wired channel: \(channelID)")
        }
        try await channelRegistry.startAll()
        logger.info("Orchestrator started with \(channels.count) channels")
    }

    /// Stop all channels gracefully.
    public func stop() async {
        await channelRegistry.stopAll()
        logger.info("Orchestrator stopped")
    }

    // MARK: - Message Pipeline

    /// Inbound message → session → agent → outbound response.
    private func handleInbound(_ message: InboundMessage) async {
        do {
            // 1. Resolve session
            let sessionKey = message.sessionKey ?? "\(message.channelID):\(message.senderID)"
            let session = try await sessionManager.session(
                for: sessionKey,
                channelID: message.channelID,
                peerID: message.senderID
            )

            // 2. Record inbound message
            let userMessage = ChatMessage(role: .user, content: message.content.textValue ?? "")
            try await sessionManager.appendMessage(userMessage, to: session.id)

            // 3. Load history
            let history = try await sessionManager.history(for: session.id)

            // 4. Route to agent and collect streamed response
            let stream = await agentRouter.route(
                message: message.content.textValue ?? "",
                session: session,
                history: history
            )

            var responseText = ""
            for try await event in stream {
                switch event {
                case .text(let chunk):
                    responseText += chunk
                case .done:
                    break
                default:
                    break
                }
            }

            // 5. Record assistant response
            let assistantMessage = ChatMessage(role: .assistant, content: responseText)
            try await sessionManager.appendMessage(assistantMessage, to: session.id)

            // 6. Deliver response back through the channel
            let outbound = OutboundMessage(
                sessionID: session.id,
                channelID: message.channelID,
                recipientID: message.senderID,
                content: .text(responseText),
                replyTo: nil
            )

            if let channel = await channelRegistry.channel(for: message.channelID) {
                try await deliver(outbound, via: channel)
            }

            // 7. Touch session
            try await sessionManager.touch(session.id)

            logger.debug("Handled message from \(message.senderID) on \(message.channelID)")
        } catch {
            logger.error("Pipeline error: \(error)")
        }
    }

    // MARK: - Delivery

    /// Chunk and send outbound message respecting channel limits.
    private func deliver(_ message: OutboundMessage, via channel: any Channel) async throws {
        guard let text = message.content.textValue else {
            try await channel.send(message)
            return
        }

        let maxLen = await channel.maxTextLength
        if text.count <= maxLen {
            try await channel.send(message)
            return
        }

        // Chunk at paragraph boundaries when possible
        let chunks = chunk(text: text, maxLength: maxLen)
        for chunk in chunks {
            let chunkedMessage = OutboundMessage(
                sessionID: message.sessionID,
                channelID: message.channelID,
                recipientID: message.recipientID,
                content: .text(chunk)
            )
            try await channel.send(chunkedMessage)
        }
    }

    /// Split text into chunks respecting max length, preferring paragraph breaks.
    private func chunk(text: String, maxLength: Int) -> [String] {
        guard text.count > maxLength else { return [text] }

        var chunks: [String] = []
        var remaining = text

        while !remaining.isEmpty {
            if remaining.count <= maxLength {
                chunks.append(remaining)
                break
            }

            let endIndex = remaining.index(remaining.startIndex, offsetBy: maxLength)
            let candidate = remaining[remaining.startIndex..<endIndex]

            // Try to break at paragraph
            if let lastNewline = candidate.lastIndex(of: "\n") {
                let breakPoint = remaining.index(after: lastNewline)
                chunks.append(String(remaining[remaining.startIndex..<breakPoint]))
                remaining = String(remaining[breakPoint...])
            } else if let lastSpace = candidate.lastIndex(of: " ") {
                let breakPoint = remaining.index(after: lastSpace)
                chunks.append(String(remaining[remaining.startIndex..<breakPoint]))
                remaining = String(remaining[breakPoint...])
            } else {
                // Hard break
                chunks.append(String(candidate))
                remaining = String(remaining[endIndex...])
            }
        }

        return chunks
    }
}
