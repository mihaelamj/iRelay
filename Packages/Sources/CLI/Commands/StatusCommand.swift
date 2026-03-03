import ArgumentParser

struct StatusCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Show gateway and channel status"
    )

    func run() throws {
        print("SwiftClaw status: idle")
    }
}
