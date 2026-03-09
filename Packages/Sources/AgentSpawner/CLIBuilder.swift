import Foundation
import Shared

public enum CLIBuilder {

    // MARK: - Public

    /// Builds a configured `Process` for the given agent spawn config and prompt.
    public static func buildProcess(
        prompt: String,
        config: AgentSpawnConfig,
        attachmentPaths: [URL] = []
    ) throws -> Process {
        let executablePath = try resolveExecutable(config.type)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.currentDirectoryURL = config.workingDirectory
        process.arguments = buildArguments(
            prompt: prompt,
            config: config,
            attachmentPaths: attachmentPaths
        )

        var env = ProcessInfo.processInfo.environment
        // Strip Claude Code session vars to avoid nesting detection
        env.removeValue(forKey: "CLAUDECODE")
        env.removeValue(forKey: "CLAUDE_CODE_SESSION")
        env.removeValue(forKey: "CLAUDE_CODE_ENTRY_POINT")
        for (key, value) in config.environment {
            env[key] = value
        }
        process.environment = env

        return process
    }

    // MARK: - Argument Construction

    static func buildArguments(
        prompt: String,
        config: AgentSpawnConfig,
        attachmentPaths: [URL] = []
    ) -> [String] {
        switch config.type {
        case .claude:
            return buildClaudeArguments(prompt: prompt, config: config)
        case .codex:
            return buildCodexArguments(
                prompt: prompt,
                config: config,
                attachmentPaths: attachmentPaths
            )
        }
    }

    // MARK: - Claude

    private static func buildClaudeArguments(
        prompt: String,
        config: AgentSpawnConfig
    ) -> [String] {
        var args: [String] = [
            "-p", prompt,
            "--output-format", "stream-json",
            "--verbose",
            "--dangerously-skip-permissions",
        ]

        if let model = config.model {
            args += ["--model", model]
        }

        if let tools = config.allowedTools, !tools.isEmpty {
            args += ["--allowedTools", tools.joined(separator: ",")]
        }

        if let systemPrompt = config.systemPrompt {
            args += ["--system-prompt", systemPrompt]
        }

        if let sessionID = config.sessionID {
            args += ["--session-id", sessionID]
        } else if config.continueSession {
            args += ["--continue"]
        }

        return args
    }

    // MARK: - Codex

    private static func buildCodexArguments(
        prompt: String,
        config: AgentSpawnConfig,
        attachmentPaths: [URL]
    ) -> [String] {
        var args: [String] = ["exec", prompt, "--json"]

        for attachment in attachmentPaths {
            args += ["-i", attachment.path]
        }

        return args
    }

    // MARK: - Executable Resolution

    static func resolveExecutable(_ agentType: AgentType) throws -> String {
        let name = agentType.executableName

        // Check common paths
        let searchPaths = [
            "/usr/local/bin/\(name)",
            "/opt/homebrew/bin/\(name)",
            "\(NSHomeDirectory())/.local/bin/\(name)",
        ]

        for path in searchPaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }

        // Fall back to which
        let whichProcess = Process()
        whichProcess.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        whichProcess.arguments = [name]
        let pipe = Pipe()
        whichProcess.standardOutput = pipe
        whichProcess.standardError = Pipe()

        do {
            try whichProcess.run()
            whichProcess.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let path = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if whichProcess.terminationStatus == 0, !path.isEmpty {
                return path
            }
        } catch {
            // Fall through to throw
        }

        throw IRelayError.agentCLINotFound(name)
    }
}
