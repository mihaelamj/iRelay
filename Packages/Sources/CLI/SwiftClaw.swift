import ArgumentParser

@main
struct SwiftClaw: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "swiftclaw",
        abstract: "Apple-native AI assistant",
        version: "0.1.0",
        subcommands: [
            ServeCommand.self,
            ChatCommand.self,
            ConfigCommand.self,
            StatusCommand.self,
            IMessageTestCommand.self,
            AgentBridgeCommand.self,
        ]
    )
}
