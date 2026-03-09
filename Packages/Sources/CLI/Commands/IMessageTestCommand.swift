import ArgumentParser
import Dispatch
import Foundation
import Shared
import ClawLogging
import IMessageChannel
import ChannelKit

struct IMessageTestCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "imessage-test",
        abstract: "Test iMessage send/receive — echo bot"
    )

    @Option(name: .shortAndLong, help: "Your phone number or Apple ID (e.g. +15551234567)")
    var recipient: String

    @Option(name: .long, help: "Poll interval in seconds")
    var poll: Double = 2.0

    @Flag(name: .long, help: "Send-only mode — sends a test message and exits")
    var sendOnly: Bool = false

    @Flag(name: .long, help: "Receive-only mode — prints inbound messages without replying")
    var receiveOnly: Bool = false

    @Option(name: .long, help: "Custom message for send-only mode")
    var message: String = "SwiftClaw test — if you see this, sending works!"

    func run() async throws {
        setbuf(stdout, nil)
        Log.bootstrap(level: .info)
        let logger = Log.cli

        print("=== SwiftClaw iMessage Test ===")
        print()

        // ---- Send-only mode (skip channel start to avoid advancing cursor) ----
        if sendOnly {
            print("Sending test message to \(recipient)...")
            #if os(macOS)
            try IMessageSender.sendText(message, to: recipient)
            #endif
            print("Sent! Check your Messages app.")
            return
        }

        // ---- Check Full Disk Access ----
        print("Step 1: Checking chat.db access...")
        let dbPath = NSHomeDirectory() + "/Library/Messages/chat.db"
        guard FileManager.default.isReadableFile(atPath: dbPath) else {
            print()
            print("ERROR: Cannot read \(dbPath)")
            print()
            print("Fix: System Settings → Privacy & Security → Full Disk Access")
            print("     → Add Terminal (or your terminal app)")
            print("     → Restart your terminal")
            throw ExitCode.failure
        }
        print("  chat.db is readable")

        // ---- Start channel ----
        print()
        print("Step 2: Starting iMessage channel (poll every \(poll)s)...")

        let config = IMessageChannelConfiguration(pollInterval: poll)
        let channel = IMessageChannel(config: config)

        await channel.onMessage { inbound in
            let text = inbound.content.textFallback
            let sender = inbound.senderID
            let time = formatTime(inbound.timestamp)

            print()
            print("[\(time)] INBOUND from \(sender):")
            print("  Content: \(text)")

            // Check for attachments
            if case .compound(let parts) = inbound.content {
                let mediaCount = parts.filter(\.isMedia).count
                if mediaCount > 0 {
                    print("  Attachments: \(mediaCount) media file(s)")
                }
            } else if inbound.content.isMedia {
                print("  Type: media attachment")
            }

            // Echo back unless receive-only
            if !receiveOnly {
                let reply = "echo: \(text)"
                let outbound = OutboundMessage(
                    sessionID: "test",
                    channelID: "imessage",
                    recipientID: sender,
                    content: .text(reply)
                )
                do {
                    try await channel.send(outbound)
                    print("  Replied: \(reply)")
                } catch {
                    print("  Send error: \(error)")
                }
            }

            fflush(stdout)
        }

        do {
            try await channel.start()
        } catch {
            print()
            print("ERROR: Failed to start iMessage channel: \(error)")
            print()
            print("Make sure Messages.app is running and you have Full Disk Access.")
            throw ExitCode.failure
        }

        print("  Channel connected!")
        print()

        if receiveOnly {
            print("Mode: RECEIVE ONLY — printing inbound messages")
        } else {
            print("Mode: ECHO BOT — replying to all messages")
        }

        print("Listening for messages from: \(recipient)")
        print("  (actually listening for ALL inbound messages)")
        print()
        print("Send a message from your phone to this Mac's iMessage.")
        print("Press Ctrl+C to stop.")
        print()
        print("---")

        // Keep alive until Ctrl+C
        let sigint = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        signal(SIGINT, SIG_IGN)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            sigint.setEventHandler {
                print("\nStopping...")
                continuation.resume()
            }
            sigint.resume()
        }
        try await channel.stop()
    }
}

private func formatTime(_ date: Date) -> String {
    let fmt = DateFormatter()
    fmt.dateFormat = "HH:mm:ss"
    return fmt.string(from: date)
}
