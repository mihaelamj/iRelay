import Foundation
import ChannelKit
import Shared
import Hummingbird
import IRelayLogging

// MARK: - Configuration

public struct WebChatChannelConfiguration: Sendable, Codable, ChannelConfiguration {
    public var channelID: String = "webchat"
    public var isEnabled: Bool = true
    public var path: String = "/chat"

    public init() {}
}

// MARK: - WebChat Channel

/// Built-in web chat UI served via Hummingbird.
/// Provides a simple HTML/JS chat interface and REST API for messaging.
public actor WebChatChannel: Channel {
    public let id = "webchat"
    public let displayName = "Web Chat"
    public let maxTextLength = Defaults.TextLimits.default

    public private(set) var status: ChannelStatus = .disconnected
    private var messageHandler: (@Sendable (InboundMessage) async -> Void)?
    private let config: WebChatChannelConfiguration
    private let logger = Log.channels
    private var pendingResponses: [String: String] = [:]

    public init(config: WebChatChannelConfiguration = .init()) {
        self.config = config
    }

    public func start() async throws {
        status = .connected
        logger.info("WebChat channel ready at \(config.path)")
    }

    public func stop() async throws {
        status = .disconnected
        logger.info("WebChat channel stopped")
    }

    public func send(_ message: OutboundMessage) async throws {
        // Store response for polling
        pendingResponses[message.recipientID] = message.content.textValue ?? ""
        logger.debug("WebChat response queued for \(message.recipientID)")
    }

    public func onMessage(_ handler: @escaping @Sendable (InboundMessage) async -> Void) {
        self.messageHandler = handler
    }

    // MARK: - HTTP Handlers (called by Gateway)

    /// Handle POST /chat/send — user sends a message.
    public func handleSend(body: Data) async throws -> Data {
        let request = try JSONDecoder().decode(WebChatRequest.self, from: body)
        let sessionID = request.sessionID ?? UUID().uuidString

        let inbound = InboundMessage(
            channelID: id,
            senderID: sessionID,
            sessionKey: "webchat:\(sessionID)",
            content: .text(request.message)
        )
        await messageHandler?(inbound)

        // Wait briefly for response
        for _ in 0..<50 {
            if let response = pendingResponses.removeValue(forKey: sessionID) {
                let reply = WebChatResponse(sessionID: sessionID, message: response)
                return try JSONEncoder().encode(reply)
            }
            try? await Task.sleep(for: .milliseconds(100))
        }

        let timeout = WebChatResponse(sessionID: sessionID, message: "(Processing...)")
        return try JSONEncoder().encode(timeout)
    }

    /// Serve the chat HTML page.
    public func chatHTML() -> String {
        """
        <!DOCTYPE html>
        <html><head><title>iRelay Chat</title>
        <style>
        body { font-family: -apple-system, sans-serif; max-width: 600px; margin: 40px auto; padding: 20px; }
        #messages { border: 1px solid #ddd; border-radius: 8px; padding: 16px; height: 400px; overflow-y: auto; margin-bottom: 16px; }
        .msg { margin: 8px 0; } .user { color: #007AFF; } .bot { color: #333; }
        #input { display: flex; gap: 8px; }
        #input input { flex: 1; padding: 8px; border: 1px solid #ddd; border-radius: 6px; }
        #input button { padding: 8px 16px; background: #007AFF; color: white; border: none; border-radius: 6px; cursor: pointer; }
        </style></head>
        <body>
        <h2>iRelay Chat</h2>
        <div id="messages"></div>
        <div id="input"><input id="msg" placeholder="Type a message..." onkeydown="if(event.key==='Enter')send()">
        <button onclick="send()">Send</button></div>
        <script>
        const sid = crypto.randomUUID();
        async function send() {
          const input = document.getElementById('msg');
          const msg = input.value.trim(); if (!msg) return;
          input.value = '';
          addMsg('You', msg, 'user');
          const res = await fetch('/chat/send', {
            method: 'POST', headers: {'Content-Type':'application/json'},
            body: JSON.stringify({sessionID: sid, message: msg})
          });
          const data = await res.json();
          addMsg('iRelay', data.message, 'bot');
        }
        function addMsg(who, text, cls) {
          const div = document.getElementById('messages');
          div.innerHTML += '<div class="msg '+cls+'"><b>'+who+':</b> '+text+'</div>';
          div.scrollTop = div.scrollHeight;
        }
        </script></body></html>
        """
    }
}

// MARK: - Types

private struct WebChatRequest: Decodable {
    let sessionID: String?
    let message: String
}

private struct WebChatResponse: Encodable {
    let sessionID: String
    let message: String
}
