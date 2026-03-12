import ArgumentParser
import Dispatch
import Foundation
import Shared
import IRelayLogging
import IMessageChannel
import ChannelKit

// MARK: - Session History

// MARK: - Bridge Session

private struct BridgeSession {
    let id: String
    var messages: [(role: String, content: String)]
}

private final class BridgeSessions: @unchecked Sendable {
    private var sessions: [String: BridgeSession] = [:]
    private let lock = NSLock()
    private let maxMessages = 40

    /// Returns the session ID for this sender (creates one if needed).
    func sessionID(for sender: String) -> String {
        lock.lock()
        defer { lock.unlock() }
        if let session = sessions[sender] {
            return session.id
        }
        let id = String(UUID().uuidString.prefix(6))
        sessions[sender] = BridgeSession(id: id, messages: [])
        return id
    }

    func append(sender: String, role: String, content: String) {
        lock.lock()
        defer { lock.unlock() }
        if sessions[sender] == nil {
            let id = String(UUID().uuidString.prefix(6))
            sessions[sender] = BridgeSession(id: id, messages: [])
        }
        sessions[sender]!.messages.append((role: role, content: content))
        if sessions[sender]!.messages.count > maxMessages {
            sessions[sender]!.messages = Array(sessions[sender]!.messages.suffix(maxMessages))
        }
    }

    func conversationContext(for sender: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        guard let session = sessions[sender], !session.messages.isEmpty else { return nil }
        return session.messages.map { "\($0.role == "user" ? "User" : "Assistant"): \($0.content)" }
            .joined(separator: "\n\n")
    }

    func messageCount(for sender: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return sessions[sender]?.messages.count ?? 0
    }

    func memorySize(for sender: String) -> String {
        lock.lock()
        defer { lock.unlock() }
        guard let session = sessions[sender] else { return "0B" }
        let bytes = session.messages.reduce(0) { $0 + $1.content.utf8.count + $1.role.utf8.count }
        if bytes < 1024 { return "\(bytes)B" }
        if bytes < 1024 * 1024 { return String(format: "%.1fKB", Double(bytes) / 1024.0) }
        return String(format: "%.1fMB", Double(bytes) / (1024.0 * 1024.0))
    }

    func clear(sender: String) {
        lock.lock()
        defer { lock.unlock() }
        sessions.removeValue(forKey: sender)
    }

    /// Save session to ~/.irelay/sessions/<sessionID>.md
    func save(sender: String) -> (path: String, id: String)? {
        lock.lock()
        defer { lock.unlock() }
        guard let session = sessions[sender], !session.messages.isEmpty else { return nil }

        let dir = NSHomeDirectory() + "/.irelay/sessions"
        try? FileManager.default.createDirectory(
            atPath: dir, withIntermediateDirectories: true
        )

        let timestamp = ISO8601DateFormatter().string(from: Date())
        let filename = "\(session.id)_\(timestamp.prefix(10)).md"
        let path = dir + "/" + filename

        var content = "# iRelay Session \(session.id)\n"
        content += "**Date:** \(timestamp)\n"
        content += "**Sender:** \(sender)\n"
        content += "**Messages:** \(session.messages.count)\n\n---\n\n"

        for msg in session.messages {
            let label = msg.role == "user" ? "**You**" : "**iRelay**"
            content += "\(label):\n\(msg.content)\n\n---\n\n"
        }

        do {
            try content.write(toFile: path, atomically: true, encoding: .utf8)
            return (path: path, id: session.id)
        } catch {
            return nil
        }
    }
}

struct AgentBridgeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "agent-bridge",
        abstract: "Bridge iMessage to Claude Code — receive prompts, stream responses"
    )

    @Option(name: .long, help: "Working directory for spawned agents")
    var workDir: String = FileManager.default.currentDirectoryPath

    @Option(name: .long, help: "Agent: claude or codex")
    var agent: String = "claude"

    @Option(name: .long, help: "Model override (e.g. claude-sonnet-4-5-20250514)")
    var model: String?

    @Option(name: .long, help: "Poll interval in seconds")
    var poll: Double = 2.0

    @Option(name: .long, help: "Max characters per iMessage chunk")
    var chunkSize: Int = 1500

    @Option(name: .long, help: "Required message prefix (case-insensitive). Messages without this prefix are ignored.")
    var prefix: String = "irelayy"

    func run() async throws {
        setbuf(stdout, nil)
        Log.bootstrap(level: .info)

        let sessions = BridgeSessions()

        print("=== iRelay Agent Bridge ===")
        print("Prefix: \(prefix)")
        print("Default agent: \(agent)")
        print("Working dir: \(workDir)")
        if let model { print("Model: \(model)") }

        let claudeOK = isCommandAvailable("claude")
        let codexOK = isCommandAvailable("codex")
        print("Agents: claude \(claudeOK ? "✓" : "✗")  codex \(codexOK ? "✓" : "✗")")
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
            let (rawText, attachmentPaths) = extractContent(from: inbound.content)
            guard !rawText.isEmpty || !attachmentPaths.isEmpty else { return }

            // Require prefix (case-insensitive) — ignore messages without it
            let lower = rawText.lowercased()
            let prefixLower = prefix.lowercased()
            guard lower.hasPrefix(prefixLower) else { return }
            let unprefixed = String(rawText.dropFirst(prefixLower.count))
                .trimmingCharacters(in: .init(charactersIn: ": ").union(.whitespacesAndNewlines))

            // Route agent based on message prefix: "codex: ..." or "@codex ..."
            let (selectedAgent, text) = parseAgentPrefix(unprefixed, defaultAgent: agent)

            print()
            print("[\(formatTime(Date()))] [\(selectedAgent)] PROMPT from \(sender): \(text)")
            if !attachmentPaths.isEmpty {
                print("  Attachments: \(attachmentPaths.map(\.lastPathComponent))")
            }
            fflush(stdout)

            let sid = sessions.sessionID(for: sender)

            // Ack
            try? await channel.send(OutboundMessage(
                sessionID: "bridge",
                channelID: "imessage",
                recipientID: sender,
                content: .text("iRelay [\(sid)]: \(selectedAgent) running...")
            ))

            // Handle "clear" / "reset" to wipe session
            if text.lowercased() == "clear" || text.lowercased() == "reset" {
                sessions.clear(sender: sender)
                try? await channel.send(OutboundMessage(
                    sessionID: "bridge",
                    channelID: "imessage",
                    recipientID: sender,
                    content: .text("📡 iRelay [\(sid)]: Session cleared.")
                ))
                return
            }

            // Handle "save" to persist session to disk
            if text.lowercased() == "save" {
                if let result = sessions.save(sender: sender) {
                    let mem = sessions.memorySize(for: sender)
                    let count = sessions.messageCount(for: sender)
                    try? await channel.send(OutboundMessage(
                        sessionID: "bridge",
                        channelID: "imessage",
                        recipientID: sender,
                        content: .text("📡 iRelay [\(sid)]: Session saved (\(count) msgs, \(mem))\n\(result.path)")
                    ))
                } else {
                    try? await channel.send(OutboundMessage(
                        sessionID: "bridge",
                        channelID: "imessage",
                        recipientID: sender,
                        content: .text("📡 iRelay [\(sid)]: Nothing to save — session is empty.")
                    ))
                }
                return
            }

            // Record user message in session
            sessions.append(sender: sender, role: "user", content: text)

            // Build prompt with conversation history
            var fullPrompt = ""
            if let context = sessions.conversationContext(for: sender) {
                // Drop the last entry (current message) since we add it below
                let lines = context.components(separatedBy: "\n\nUser: \(text)")
                let prior = lines.first ?? ""
                if !prior.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    fullPrompt += "Previous conversation:\n\(prior)\n\n---\n\nNow respond to:\n"
                }
            }
            fullPrompt += text

            if selectedAgent != "codex", !attachmentPaths.isEmpty {
                let paths = attachmentPaths.map(\.path).joined(separator: "\n")
                fullPrompt += "\n\nAttached files:\n\(paths)"
            }

            // Run agent via shell — simple and reliable
            let result = await runAgent(
                prompt: fullPrompt,
                workDir: workDir,
                agent: selectedAgent,
                model: model,
                attachmentPaths: attachmentPaths
            )

            // Record assistant response in session
            sessions.append(sender: sender, role: "assistant", content: result)

            print("  [result] \(result.prefix(100))...")
            fflush(stdout)

            // Send response in chunks, prefix first chunk with iRelay header
            let chunks = splitMessage(result, maxLength: chunkSize)
            for (i, chunk) in chunks.enumerated() {
                let msgNum = sessions.messageCount(for: sender) / 2
                let mem = sessions.memorySize(for: sender)
                let body = i == 0 ? "📡 iRelay [\(sid)] #\(msgNum) (\(mem)):\n\(chunk)" : chunk
                try? await channel.send(OutboundMessage(
                    sessionID: "bridge",
                    channelID: "imessage",
                    recipientID: sender,
                    content: .text(body)
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

/// Check if a CLI tool is available on the system.
private func isCommandAvailable(_ name: String) -> Bool {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
    process.arguments = [name]
    process.standardOutput = Pipe()
    process.standardError = Pipe()
    do {
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus == 0
    } catch {
        return false
    }
}

/// Run an agent CLI as a shell subprocess and return the plain text result.
private func runAgent(
    prompt: String,
    workDir: String,
    agent: String,
    model: String?,
    attachmentPaths: [URL]
) async -> String {
    let cliName = agent == "codex" ? "codex" : "claude"
    guard isCommandAvailable(cliName) else {
        return "❌ \(cliName) is not installed. Install it first to use the \(agent) agent."
    }

    return await withCheckedContinuation { continuation in
        DispatchQueue.global().async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")

            let shellCommand: String
            switch agent {
            case "codex":
                // codex exec "<prompt>" --full-auto [-i file1 -i file2]
                var cmd = "codex exec --full-auto"
                let inputs = attachmentPaths.map { "-i '\($0.path)'" }.joined(separator: " ")
                if !inputs.isEmpty { cmd += " \(inputs)" }
                shellCommand = """
                    cd '\(workDir)' && \(cmd) <<'IRELAY_PROMPT'
                    \(prompt)
                    IRELAY_PROMPT
                    """
            default:
                // claude -p "<prompt>" --dangerously-skip-permissions
                var cmd = "claude -p"
                if let model { cmd += " --model '\(model)'" }
                shellCommand = """
                    cd '\(workDir)' && \(cmd) --dangerously-skip-permissions <<'IRELAY_PROMPT'
                    \(prompt)
                    IRELAY_PROMPT
                    """
            }
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

/// Parse agent prefix from message. Supports "codex: ...", "@codex ...", "claude: ...", "@claude ...".
private func parseAgentPrefix(_ text: String, defaultAgent: String) -> (agent: String, prompt: String) {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    let lower = trimmed.lowercased()

    let prefixes: [(pattern: String, agent: String)] = [
        ("codex:", "codex"),
        ("@codex ", "codex"),
        ("claude:", "claude"),
        ("@claude ", "claude"),
    ]

    for (pattern, agent) in prefixes {
        if lower.hasPrefix(pattern) {
            let prompt = String(trimmed.dropFirst(pattern.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (agent, prompt)
        }
    }

    return (defaultAgent, trimmed)
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
        .appendingPathComponent(".irelay/bridge-attachments")
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
