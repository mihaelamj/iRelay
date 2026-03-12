import ArgumentParser
import Foundation
import Shared
import IRelayLogging
import Storage
import IRelaySecurity
import Sessions
import Agents
import ProviderKit
import ClaudeProvider

struct ChatCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "chat",
        abstract: "Interactive CLI chat"
    )

    @Option(name: .shortAndLong, help: "Model ID to use")
    var model: String = Defaults.defaultModelID

    @Option(name: .shortAndLong, help: "System prompt")
    var system: String = "You are a helpful assistant."

    func run() async throws {
        Log.bootstrap(level: .warning) // quiet for chat mode
        let logger = Log.cli

        // Set up minimal pipeline: provider → agent
        let keychain = KeychainStore()
        guard let apiKey = try keychain.apiKey(for: "claude")
            ?? ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] else {
            print("Error: No API key. Set ANTHROPIC_API_KEY or run: irelay config set-key claude <key>")
            throw ExitCode.failure
        }

        let providerRegistry = ProviderRegistry()
        let claude = ClaudeProvider(apiKey: apiKey)
        await providerRegistry.register(claude)

        let agentRouter = AgentRouter(providers: providerRegistry)
        let agent = Agent(
            id: "cli",
            name: "CLI Chat",
            systemPrompt: system,
            providerID: "claude",
            modelID: model
        )
        await agentRouter.register(agent)

        // In-memory session
        let session = Session(
            id: "cli-session",
            metadata: SessionMetadata(
                agentID: "cli",
                channelID: "cli",
                peerID: "user"
            )
        )

        var history: [ChatMessage] = []

        print("iRelay Chat (model: \(model))")
        print("Type 'exit' or Ctrl+D to quit.\n")

        while true {
            print("> ", terminator: "")
            guard let input = readLine(), !input.isEmpty else {
                if readLine() == nil { break } // EOF
                continue
            }
            if input.lowercased() == "exit" { break }

            history.append(ChatMessage(role: .user, text: input))

            let stream = await agentRouter.invoke(
                agent: agent,
                message: input,
                session: session,
                history: history
            )

            var response = ""
            do {
                for try await event in stream {
                    switch event {
                    case .text(let chunk):
                        print(chunk, terminator: "")
                        response += chunk
                    case .done:
                        print() // newline after response
                    default:
                        break
                    }
                }
            } catch {
                print("\nError: \(error)")
                logger.error("Chat error: \(error)")
            }

            if !response.isEmpty {
                history.append(ChatMessage(role: .assistant, text: response))
            }
            print()
        }

        print("Goodbye!")
    }
}
