import ArgumentParser

struct ServeCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "serve",
        abstract: "Start gateway and all channels"
    )

    func run() throws {
        print("Starting SwiftClaw gateway...")
    }
}
