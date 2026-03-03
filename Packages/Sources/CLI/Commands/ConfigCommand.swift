import ArgumentParser

struct ConfigCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "config",
        abstract: "Manage agents, channels, providers"
    )

    func run() throws {
        print("Configuration manager")
    }
}
