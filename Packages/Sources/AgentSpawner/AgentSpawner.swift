import Foundation
import ClawLogging
import Shared

// MARK: - Running Agent

struct RunningAgent: @unchecked Sendable {
    let session: AgentSession
    let process: Process
    let task: Task<Void, Never>
}

// MARK: - AgentSpawner

public actor AgentSpawner {
    private var activeAgents: [UUID: RunningAgent] = [:]
    private let maxConcurrent: Int
    private let maxPerSender: Int

    public init(
        maxConcurrent: Int = Defaults.Spawner.maxConcurrentAgents,
        maxPerSender: Int = Defaults.Spawner.maxAgentsPerSender
    ) {
        self.maxConcurrent = maxConcurrent
        self.maxPerSender = maxPerSender
    }

    // MARK: - Spawn

    public func spawn(
        prompt: String,
        config: AgentSpawnConfig,
        senderID: String,
        attachmentPaths: [URL] = []
    ) throws -> (sessionID: UUID, stream: AsyncThrowingStream<AgentStreamEvent, Error>) {
        // Check global concurrency
        if activeAgents.count >= maxConcurrent {
            throw SwiftClawError.agentTooManyActive(
                current: activeAgents.count,
                max: maxConcurrent
            )
        }

        // Check per-sender concurrency
        let senderCount = activeAgents.values.filter { $0.session.senderID == senderID }.count
        if senderCount >= maxPerSender {
            throw SwiftClawError.agentTooManyActive(
                current: senderCount,
                max: maxPerSender
            )
        }

        let sessionID = UUID()
        let process = try CLIBuilder.buildProcess(
            prompt: prompt,
            config: config,
            attachmentPaths: attachmentPaths
        )

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        // Close stdin immediately so the child doesn't block waiting for input
        try? stdinPipe.fileHandleForWriting.close()

        let session = AgentSession(
            id: sessionID,
            agentType: config.type,
            senderID: senderID,
            prompt: prompt,
            workingDirectory: config.workingDirectory
        )

        let parser: StreamParser = config.type == .claude
            ? ClaudeStreamParser()
            : CodexStreamParser()

        let coalescer = ProgressCoalescer()
        let timeoutInterval = config.timeout
        let idleTimeoutInterval = config.idleTimeout

        let stream = AsyncThrowingStream<AgentStreamEvent, Error> { continuation in
            let task = Task { [weak self] in
                // Launch process
                do {
                    try process.run()
                } catch {
                    continuation.yield(.error("Failed to launch process: \(error.localizedDescription)"))
                    continuation.finish()
                    await self?.removeAgent(sessionID)
                    return
                }

                Log.spawner.info("Spawned \(config.type.rawValue) agent \(sessionID)")

                // Overall timeout
                let timeoutTask = Task {
                    try await Task.sleep(nanoseconds: UInt64(timeoutInterval * 1_000_000_000))
                    process.terminate()
                    continuation.yield(.error("Agent timed out after \(Int(timeoutInterval))s"))
                    continuation.finish(throwing: SwiftClawError.agentTimeout(seconds: Int(timeoutInterval)))
                }

                // Idle timeout tracking
                let lastActivity = LastActivity()
                let idleTask = Task {
                    while !Task.isCancelled {
                        try await Task.sleep(nanoseconds: 5_000_000_000) // check every 5s
                        let elapsed = Date().timeIntervalSince(lastActivity.date)
                        if elapsed >= idleTimeoutInterval {
                            process.terminate()
                            continuation.yield(.error("Agent idle timeout after \(Int(idleTimeoutInterval))s"))
                            continuation.finish(
                                throwing: SwiftClawError.agentIdleTimeout(seconds: Int(idleTimeoutInterval))
                            )
                            return
                        }
                    }
                }

                // Read stdout line by line
                let handle = stdoutPipe.fileHandleForReading
                do {
                    for try await line in handle.bytes.lines {
                        guard !Task.isCancelled else { break }
                        lastActivity.touch()

                        if let event = parser.parse(line: line) {
                            if let filtered = await coalescer.filter(event) {
                                // Capture session_id from done events
                                if case .done(_, let agentSessionID) = filtered {
                                    await self?.updateSessionID(sessionID, agentSessionID: agentSessionID)
                                }
                                continuation.yield(filtered)
                            }
                        }
                    }
                } catch {
                    if !Task.isCancelled {
                        continuation.yield(.error("Stream read error: \(error.localizedDescription)"))
                    }
                }

                // Process finished
                process.waitUntilExit()
                timeoutTask.cancel()
                idleTask.cancel()

                let exitCode = process.terminationStatus
                if exitCode != 0 {
                    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                    let stderrText = String(data: stderrData, encoding: .utf8) ?? ""
                    continuation.yield(.error("Process exited with code \(exitCode): \(stderrText)"))
                    continuation.finish(
                        throwing: SwiftClawError.agentNonZeroExit(code: exitCode, stderr: stderrText)
                    )
                } else {
                    continuation.finish()
                }

                await self?.removeAgent(sessionID)
                Log.spawner.info("Agent \(sessionID) finished (exit \(exitCode))")
            }

            // Register the running agent
            Task { [weak self] in
                await self?.registerAgent(
                    sessionID: sessionID,
                    agent: RunningAgent(session: session, process: process, task: task)
                )
            }

            continuation.onTermination = { @Sendable _ in
                if process.isRunning {
                    process.terminate()
                }
                task.cancel()
            }
        }

        return (sessionID: sessionID, stream: stream)
    }

    // MARK: - Cancel

    public func cancel(_ sessionID: UUID) {
        guard let agent = activeAgents[sessionID] else { return }
        if agent.process.isRunning {
            agent.process.terminate()
        }
        agent.task.cancel()
        activeAgents.removeValue(forKey: sessionID)
        Log.spawner.info("Cancelled agent \(sessionID)")
    }

    public func cancelAll(for senderID: String) {
        let toCancel = activeAgents.filter { $0.value.session.senderID == senderID }
        for (id, _) in toCancel {
            cancel(id)
        }
    }

    // MARK: - Queries

    public var sessions: [AgentSession] {
        activeAgents.values.map(\.session)
    }

    public func isActive(for senderID: String) -> Bool {
        activeAgents.values.contains { $0.session.senderID == senderID }
    }

    public func session(for id: UUID) -> AgentSession? {
        activeAgents[id]?.session
    }

    // MARK: - Internal

    private func registerAgent(sessionID: UUID, agent: RunningAgent) {
        activeAgents[sessionID] = agent
    }

    private func removeAgent(_ sessionID: UUID) {
        activeAgents.removeValue(forKey: sessionID)
    }

    private func updateSessionID(_ sessionID: UUID, agentSessionID: String?) {
        guard var agent = activeAgents[sessionID], let agentSessionID else { return }
        var session = agent.session
        session.agentSessionID = agentSessionID
        agent = RunningAgent(session: session, process: agent.process, task: agent.task)
        activeAgents[sessionID] = agent
    }
}

// MARK: - LastActivity

/// Mutable reference type for tracking last activity time across tasks.
final class LastActivity: @unchecked Sendable {
    private let lock = NSLock()
    private var _date = Date()

    var date: Date {
        lock.lock()
        defer { lock.unlock() }
        return _date
    }

    func touch() {
        lock.lock()
        _date = Date()
        lock.unlock()
    }
}
