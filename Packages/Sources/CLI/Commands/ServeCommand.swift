import ArgumentParser
import Foundation
import Shared
import IRelayLogging
import Storage
import IRelaySecurity
import Sessions
import Agents
import ProviderKit
import ChannelKit
import Services
import ClaudeProvider
import TelegramChannel

struct ServeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "serve",
        abstract: "Start gateway and all channels"
    )

    @Option(name: .shortAndLong, help: "Config file path")
    var config: String?

    @Option(name: .shortAndLong, help: "Log level (trace, debug, info, warning, error)")
    var logLevel: String = "info"

    func run() async throws {
        // 1. Bootstrap logging
        let level = parseLogLevel(logLevel)
        Log.bootstrap(level: level)
        let logger = Log.cli

        logger.info("iRelay v\(IRelayVersion.current) starting...")

        // 2. Load config
        let configURL = config.map { URL(fileURLWithPath: $0) }
        let appConfig = try IRelayConfig.load(from: configURL ?? IRelayPaths.configFile)

        // 3. Initialize database
        let db = try IRelayDatabase()
        try db.migrate()
        logger.info("Database ready")

        // 4. Set up providers
        let providerRegistry = ProviderRegistry()
        let keychain = KeychainStore()

        if let claudeKey = try keychain.apiKey(for: "claude")
            ?? ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] {
            let claude = ClaudeProvider(apiKey: claudeKey)
            await providerRegistry.register(claude)
            logger.info("Claude provider registered")
        }

        // 5. Set up agents
        let agentRouter = AgentRouter(providers: providerRegistry)

        // Register default agent from config
        for agentDef in appConfig.agents.agents {
            let agent = Agent(
                id: agentDef.id,
                name: agentDef.name,
                systemPrompt: agentDef.systemPrompt,
                providerID: agentDef.providerID ?? "claude",
                modelID: agentDef.modelID ?? appConfig.agents.defaultModelID
            )
            await agentRouter.register(agent)
        }

        // Ensure at least a default agent exists
        if await agentRouter.registeredIDs.isEmpty {
            let defaultAgent = Agent(
                id: Defaults.defaultAgentID,
                name: "Main Assistant",
                providerID: "claude",
                modelID: appConfig.agents.defaultModelID
            )
            await agentRouter.register(defaultAgent)
        }

        // 6. Set up sessions
        let sessionManager = SessionManager(db: db)

        // 7. Set up channels
        let channelRegistry = ChannelRegistry()

        // Telegram
        if let tgEntry = appConfig.channels.enabled["telegram"],
           tgEntry.isEnabled,
           let botToken = tgEntry.settings["botToken"]
               ?? ProcessInfo.processInfo.environment["TELEGRAM_BOT_TOKEN"] {
            let tgConfig = TelegramChannelConfiguration(
                botToken: botToken,
                webhookURL: tgEntry.settings["webhookURL"]
            )
            let telegram = TelegramChannel(config: tgConfig)
            await channelRegistry.register(telegram)
            logger.info("Telegram channel registered")
        }

        // 8. Start orchestrator
        let orchestrator = ServiceOrchestrator(
            sessionManager: sessionManager,
            agentRouter: agentRouter,
            channelRegistry: channelRegistry
        )

        try await orchestrator.start()
        logger.info("iRelay is running. Press Ctrl+C to stop.")

        // Keep alive until signal
        await withCheckedContinuation { (_: CheckedContinuation<Void, Never>) in
            signal(SIGINT) { _ in
                print("\nShutting down...")
                Darwin.exit(0)
            }
            signal(SIGTERM) { _ in
                print("\nShutting down...")
                Darwin.exit(0)
            }
        }
    }

    private func parseLogLevel(_ string: String) -> Logging.Logger.Level {
        switch string.lowercased() {
        case "trace": return .trace
        case "debug": return .debug
        case "info": return .info
        case "warning", "warn": return .warning
        case "error": return .error
        case "critical": return .critical
        default: return .info
        }
    }
}

import Logging
