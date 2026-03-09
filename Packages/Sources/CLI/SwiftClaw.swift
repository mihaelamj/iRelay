import ArgumentParser

@main
struct IRelay: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "irelay",
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
