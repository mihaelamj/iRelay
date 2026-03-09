import ArgumentParser
import Dispatch
import Foundation
import Shared
import ClawLogging
import IMessageChannel
import ChannelKit

struct AgentBridgeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "agent-bridge",
        abstract: "Bridge iMessage to Claude Code — receive prompts, stream responses"
    )

    @Option(name: .long, help: "Working directory for spawned agents")
    var workDir: String = FileManager.default.currentDirectoryPath

    @Option(name: .long, help: "Model override (e.g. claude-sonnet-4-5-20250514)")
    var model: String?

    @Option(name: .long, help: "Poll interval in seconds")
    var poll: Double = 2.0

    @Option(name: .long, help: "Max characters per iMessage chunk")
    var chunkSize: Int = 1500

    func run() async throws {
        setbuf(stdout, nil)
        Log.bootstrap(level: .info)

        print("=== SwiftClaw Agent Bridge ===")
        print("Working dir: \(workDir)")
        if let model { print("Model: \(model)") }
        print()

        // ---- Check Full Disk Access ----
        let dbPath = NSHomeDirectory() + "/Library/Messages/chat.db"
        guard FileManager.default.isReadableFile(atPath: dbPath) else {
            print("ERROR: Cannot read \(dbPath)")
            throw ExitCode.failure
        }

        // ---- Start iMessage channel ----
        let channelConfig = IMessageChannelConfiguration(pollInterval: poll)
        let channel = IMessageChannel(config: channelConfig)

        await channel.onMessage { inbound in
            let sender = inbound.senderID

            // Extract text and save any attachments to disk
            let (text, attachmentPaths) = extractContent(from: inbound.content)
            guard !text.isEmpty || !attachmentPaths.isEmpty else { return }

            print()
            print("[\(formatTime(Date()))] PROMPT from \(sender): \(text)")
            if !attachmentPaths.isEmpty {
                print("  Attachments: \(attachmentPaths.map(\.lastPathComponent))")
            }
            fflush(stdout)

            // Ack
            try? await channel.send(OutboundMessage(
                sessionID: "bridge",
                channelID: "imessage",
                recipientID: sender,
                content: .text("⚡ Running...")
            ))

            // Build prompt with attachment paths
            var fullPrompt = text
            if !attachmentPaths.isEmpty {
                let paths = attachmentPaths.map(\.path).joined(separator: "\n")
                fullPrompt += "\n\nAttached files:\n\(paths)"
            }

            // Run claude via shell — simple and reliable
            let result = await runClaude(prompt: fullPrompt, workDir: workDir, model: model)

            print("  [result] \(result.prefix(100))...")
            fflush(stdout)

            // Send response in chunks
            let chunks = splitMessage(result, maxLength: chunkSize)
            for chunk in chunks {
                try? await channel.send(OutboundMessage(
                    sessionID: "bridge",
                    channelID: "imessage",
                    recipientID: sender,
                    content: .text(chunk)
                ))
            }
        }

        do {
            try await channel.start()
        } catch {
            print("ERROR: Failed to start iMessage channel: \(error)")
            throw ExitCode.failure
        }

        print("Bridge connected! Listening for prompts...")
        print("Press Ctrl+C to stop.")
        print("---")
        fflush(stdout)

        // Keep alive until Ctrl+C
        let sigint = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        signal(SIGINT, SIG_IGN)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            sigint.setEventHandler {
                print("\nShutting down bridge...")
                continuation.resume()
            }
            sigint.resume()
        }

        try await channel.stop()
    }
}

/// Run `claude -p` as a shell subprocess and return the plain text result.
private func runClaude(prompt: String, workDir: String, model: String?) async -> String {
    await withCheckedContinuation { continuation in
        DispatchQueue.global().async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")

            // Build the claude command
            var cmd = "claude -p"
            if let model {
                cmd += " --model '\(model)'"
            }
            // Use heredoc to safely pass the prompt without shell escaping issues
            let shellCommand = """
                cd '\(workDir)' && \(cmd) --dangerously-skip-permissions <<'SWIFTCLAW_PROMPT'
                \(prompt)
                SWIFTCLAW_PROMPT
                """
            process.arguments = ["-c", shellCommand]

            // Strip Claude Code env vars to avoid nesting detection
            var env = ProcessInfo.processInfo.environment
            env.removeValue(forKey: "CLAUDECODE")
            env.removeValue(forKey: "CLAUDE_CODE_SESSION")
            env.removeValue(forKey: "CLAUDE_CODE_ENTRY_POINT")
            process.environment = env

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            do {
                try process.run()
                process.waitUntilExit()

                let outData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: outData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                if process.terminationStatus != 0, output.isEmpty {
                    let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                    let errText = String(data: errData, encoding: .utf8) ?? "Unknown error"
                    continuation.resume(returning: "❌ Error: \(errText)")
                } else {
                    continuation.resume(returning: output.isEmpty ? "No response from Claude." : output)
                }
            } catch {
                continuation.resume(returning: "❌ Failed to launch: \(error.localizedDescription)")
            }
        }
    }
}

private func formatTime(_ date: Date) -> String {
    let fmt = DateFormatter()
    fmt.dateFormat = "HH:mm:ss"
    return fmt.string(from: date)
}

/// Extract text and save attachments to disk, returning their file URLs.
private func extractContent(from content: MessageContent) -> (text: String, attachments: [URL]) {
    var text = ""
    var attachments: [URL] = []

    func process(_ content: MessageContent) {
        switch content {
        case .text(let value):
            text += value
        case .image(let data, let mimeType):
            let ext = fileExtension(for: mimeType)
            if let url = saveAttachment(data: data, name: "image.\(ext)") {
                attachments.append(url)
            }
        case .video(let data, let mimeType):
            let ext = fileExtension(for: mimeType)
            if let url = saveAttachment(data: data, name: "video.\(ext)") {
                attachments.append(url)
            }
        case .audio(let data, let mimeType):
            let ext = fileExtension(for: mimeType)
            if let url = saveAttachment(data: data, name: "audio.\(ext)") {
                attachments.append(url)
            }
        case .file(let data, let filename, _):
            if let url = saveAttachment(data: data, name: filename) {
                attachments.append(url)
            }
        case .compound(let parts):
            for part in parts {
                process(part)
            }
        case .link(let url, _):
            text += url.absoluteString
        case .location:
            break
        }
    }

    process(content)
    return (text.trimmingCharacters(in: .whitespacesAndNewlines), attachments)
}

private func saveAttachment(data: Data, name: String) -> URL? {
    let dir = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent(".swiftclaw/bridge-attachments")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

    let uuid = UUID().uuidString.prefix(8)
    let url = dir.appendingPathComponent("\(uuid)-\(name)")
    do {
        try data.write(to: url)
        return url
    } catch {
        print("  Failed to save attachment: \(error)")
        return nil
    }
}

private func fileExtension(for mimeType: String) -> String {
    switch mimeType {
    case "image/jpeg": "jpg"
    case "image/png": "png"
    case "image/heic": "heic"
    case "image/gif": "gif"
    case "image/webp": "webp"
    case "video/mp4": "mp4"
    case "video/quicktime": "mov"
    case "audio/mpeg": "mp3"
    case "audio/aac": "aac"
    case "application/pdf": "pdf"
    default: "bin"
    }
}

private func splitMessage(_ text: String, maxLength: Int) -> [String] {
    guard text.count > maxLength else { return [text] }

    var chunks: [String] = []
    var remaining = text

    while !remaining.isEmpty {
        if remaining.count <= maxLength {
            chunks.append(remaining)
            break
        }
        let prefix = String(remaining.prefix(maxLength))
        if let lastNewline = prefix.lastIndex(of: "\n") {
            let chunk = String(remaining[remaining.startIndex...lastNewline])
            chunks.append(chunk)
            remaining = String(remaining[remaining.index(after: lastNewline)...])
        } else {
            chunks.append(prefix)
            remaining = String(remaining.dropFirst(maxLength))
        }
    }
    return chunks
}
