import ArgumentParser

struct ChatCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "chat",
        abstract: "Interactive CLI chat"
    )

    func run() throws {
        print("Starting interactive chat...")
    }
}
