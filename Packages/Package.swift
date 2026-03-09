// swift-tools-version: 6.0

import PackageDescription

// -------------------------------------------------------------

// MARK: Products

// -------------------------------------------------------------

let allProducts: [Product] = [
    // Foundation Layer
    .singleTargetLibrary("Shared"),
    .singleTargetLibrary("ClawLogging"),
    .singleTargetLibrary("ClawSecurity"),
    .singleTargetLibrary("Storage"),
    .singleTargetLibrary("Networking"),

    // Protocol Layer
    .singleTargetLibrary("ChannelKit"),
    .singleTargetLibrary("ProviderKit"),

    // Channel Implementations
    .singleTargetLibrary("IMessageChannel"),
    .singleTargetLibrary("WhatsAppChannel"),
    .singleTargetLibrary("TelegramChannel"),
    .singleTargetLibrary("SlackChannel"),
    .singleTargetLibrary("DiscordChannel"),
    .singleTargetLibrary("SignalChannel"),
    .singleTargetLibrary("MatrixChannel"),
    .singleTargetLibrary("IRCChannel"),
    .singleTargetLibrary("WebChatChannel"),

    // Provider Implementations
    .singleTargetLibrary("ClaudeProvider"),
    .singleTargetLibrary("OpenAIProvider"),
    .singleTargetLibrary("OllamaProvider"),
    .singleTargetLibrary("GeminiProvider"),

    // Core Layer
    .singleTargetLibrary("Gateway"),
    .singleTargetLibrary("Sessions"),
    .singleTargetLibrary("Agents"),
    .singleTargetLibrary("AgentSpawner"),
    .singleTargetLibrary("Scheduling"),
    .singleTargetLibrary("Voice"),
    .singleTargetLibrary("Memory"),
    .singleTargetLibrary("MCPSupport"),
    .singleTargetLibrary("Services"),

    // Executables
    .executable(name: "swiftclaw", targets: ["CLI"]),
]

// -------------------------------------------------------------

// MARK: Dependencies

// -------------------------------------------------------------

let deps: [Package.Dependency] = [
    // Server
    .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.0.0"),
    .package(url: "https://github.com/hummingbird-project/hummingbird-websocket.git", from: "2.0.0"),

    // CLI
    .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),

    // Database
    .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),

    // Logging
    .package(url: "https://github.com/apple/swift-log.git", from: "1.5.0"),

    // DI (uncomment when needed)
    // .package(url: "https://github.com/pointfreeco/swift-dependencies.git", from: "1.0.0"),
]

// -------------------------------------------------------------

// MARK: Targets

// -------------------------------------------------------------

let targets: [Target] = {

    // ---------- Foundation Layer ----------

    let sharedTarget = Target.target(
        name: "Shared",
        dependencies: []
    )
    let sharedTestsTarget = Target.testTarget(
        name: "SharedTests",
        dependencies: ["Shared", "TestSupport"]
    )

    let loggingTarget = Target.target(
        name: "ClawLogging",
        dependencies: [
            "Shared",
            .product(name: "Logging", package: "swift-log"),
        ]
    )
    let loggingTestsTarget = Target.testTarget(
        name: "ClawLoggingTests",
        dependencies: ["ClawLogging", "TestSupport"]
    )

    let securityTarget = Target.target(
        name: "ClawSecurity",
        dependencies: ["Shared"]
    )
    let securityTestsTarget = Target.testTarget(
        name: "ClawSecurityTests",
        dependencies: ["ClawSecurity", "TestSupport"]
    )

    let storageTarget = Target.target(
        name: "Storage",
        dependencies: [
            "Shared",
            "ClawLogging",
            .product(name: "GRDB", package: "GRDB.swift"),
        ]
    )
    let storageTestsTarget = Target.testTarget(
        name: "StorageTests",
        dependencies: ["Storage", "TestSupport"]
    )

    let networkingTarget = Target.target(
        name: "Networking",
        dependencies: ["Shared", "ClawLogging"]
    )
    let networkingTestsTarget = Target.testTarget(
        name: "NetworkingTests",
        dependencies: ["Networking", "TestSupport"]
    )

    // ---------- Protocol Layer ----------

    let channelKitTarget = Target.target(
        name: "ChannelKit",
        dependencies: ["Shared", "ClawLogging"]
    )
    let channelKitTestsTarget = Target.testTarget(
        name: "ChannelKitTests",
        dependencies: ["ChannelKit", "TestSupport"]
    )

    let providerKitTarget = Target.target(
        name: "ProviderKit",
        dependencies: ["Shared", "ClawLogging"]
    )
    let providerKitTestsTarget = Target.testTarget(
        name: "ProviderKitTests",
        dependencies: ["ProviderKit", "TestSupport"]
    )

    // ---------- Channel Implementations ----------

    let iMessageChannelTarget = Target.target(
        name: "IMessageChannel",
        dependencies: [
            "ChannelKit",
            "Shared",
            "ClawLogging",
            .product(name: "GRDB", package: "GRDB.swift"),
        ]
    )
    let iMessageChannelTestsTarget = Target.testTarget(
        name: "IMessageChannelTests",
        dependencies: ["IMessageChannel", "TestSupport"]
    )

    let whatsAppChannelTarget = Target.target(
        name: "WhatsAppChannel",
        dependencies: ["ChannelKit", "Shared", "Networking"]
    )
    let whatsAppChannelTestsTarget = Target.testTarget(
        name: "WhatsAppChannelTests",
        dependencies: ["WhatsAppChannel", "TestSupport"]
    )

    let telegramChannelTarget = Target.target(
        name: "TelegramChannel",
        dependencies: ["ChannelKit", "Shared", "Networking"]
    )
    let telegramChannelTestsTarget = Target.testTarget(
        name: "TelegramChannelTests",
        dependencies: ["TelegramChannel", "TestSupport"]
    )

    let slackChannelTarget = Target.target(
        name: "SlackChannel",
        dependencies: ["ChannelKit", "Shared", "Networking"]
    )
    let slackChannelTestsTarget = Target.testTarget(
        name: "SlackChannelTests",
        dependencies: ["SlackChannel", "TestSupport"]
    )

    let discordChannelTarget = Target.target(
        name: "DiscordChannel",
        dependencies: ["ChannelKit", "Shared", "Networking"]
    )

    let signalChannelTarget = Target.target(
        name: "SignalChannel",
        dependencies: ["ChannelKit", "Shared"]
    )

    let matrixChannelTarget = Target.target(
        name: "MatrixChannel",
        dependencies: ["ChannelKit", "Shared", "Networking"]
    )

    let ircChannelTarget = Target.target(
        name: "IRCChannel",
        dependencies: ["ChannelKit", "Shared"]
    )

    let webChatChannelTarget = Target.target(
        name: "WebChatChannel",
        dependencies: [
            "ChannelKit",
            "Shared",
            .product(name: "Hummingbird", package: "hummingbird"),
        ]
    )

    // ---------- Provider Implementations ----------

    let claudeProviderTarget = Target.target(
        name: "ClaudeProvider",
        dependencies: ["ProviderKit", "Shared", "Networking"]
    )
    let claudeProviderTestsTarget = Target.testTarget(
        name: "ClaudeProviderTests",
        dependencies: ["ClaudeProvider", "TestSupport"]
    )

    let openAIProviderTarget = Target.target(
        name: "OpenAIProvider",
        dependencies: ["ProviderKit", "Shared", "Networking"]
    )
    let openAIProviderTestsTarget = Target.testTarget(
        name: "OpenAIProviderTests",
        dependencies: ["OpenAIProvider", "TestSupport"]
    )

    let ollamaProviderTarget = Target.target(
        name: "OllamaProvider",
        dependencies: ["ProviderKit", "Shared", "Networking"]
    )

    let geminiProviderTarget = Target.target(
        name: "GeminiProvider",
        dependencies: ["ProviderKit", "Shared", "Networking"]
    )

    // ---------- Core Layer ----------

    let gatewayTarget = Target.target(
        name: "Gateway",
        dependencies: [
            "Shared",
            "ClawLogging",
            .product(name: "Hummingbird", package: "hummingbird"),
            .product(name: "HummingbirdWebSocket", package: "hummingbird-websocket"),
        ]
    )
    let gatewayTestsTarget = Target.testTarget(
        name: "GatewayTests",
        dependencies: ["Gateway", "TestSupport"]
    )

    let sessionsTarget = Target.target(
        name: "Sessions",
        dependencies: [
            "Shared",
            "ClawLogging",
            "Storage",
            .product(name: "GRDB", package: "GRDB.swift"),
        ]
    )
    let sessionsTestsTarget = Target.testTarget(
        name: "SessionsTests",
        dependencies: ["Sessions", "TestSupport"]
    )

    let agentsTarget = Target.target(
        name: "Agents",
        dependencies: ["Shared", "ClawLogging", "ProviderKit", "Sessions"]
    )

    let agentSpawnerTarget = Target.target(
        name: "AgentSpawner",
        dependencies: ["Shared", "ClawLogging"]
    )
    let agentSpawnerTestsTarget = Target.testTarget(
        name: "AgentSpawnerTests",
        dependencies: ["AgentSpawner", "TestSupport"]
    )

    let schedulingTarget = Target.target(
        name: "Scheduling",
        dependencies: ["Shared", "ClawLogging"]
    )

    let voiceTarget = Target.target(
        name: "Voice",
        dependencies: ["Shared", "ClawLogging"]
    )
    let voiceTestsTarget = Target.testTarget(
        name: "VoiceTests",
        dependencies: ["Voice", "TestSupport"]
    )

    let memoryTarget = Target.target(
        name: "Memory",
        dependencies: [
            "Shared",
            "ClawLogging",
            "Storage",
            "ProviderKit",
            .product(name: "GRDB", package: "GRDB.swift"),
        ]
    )
    let memoryTestsTarget = Target.testTarget(
        name: "MemoryTests",
        dependencies: ["Memory", "TestSupport"]
    )

    let mcpSupportTarget = Target.target(
        name: "MCPSupport",
        dependencies: ["Shared", "ClawLogging"]
    )

    // ---------- Service Layer ----------

    let servicesTarget = Target.target(
        name: "Services",
        dependencies: [
            "Sessions",
            "Agents",
            "ChannelKit",
            "ProviderKit",
            "Shared",
            "Storage",
            "Scheduling",
            "ClawLogging",
        ]
    )

    // ---------- Executable ----------

    let cliTarget = Target.executableTarget(
        name: "CLI",
        dependencies: [
            "Services",
            "Gateway",
            "Shared",
            "ClawLogging",
            // Channels
            "IMessageChannel",
            "WhatsAppChannel",
            "TelegramChannel",
            "SlackChannel",
            "DiscordChannel",
            "SignalChannel",
            "MatrixChannel",
            "IRCChannel",
            "WebChatChannel",
            // Providers
            "ClaudeProvider",
            "OpenAIProvider",
            "OllamaProvider",
            "GeminiProvider",
            // Core
            "ClawSecurity",
            "Storage",
            "Sessions",
            "Agents",
            // Features
            "Voice",
            "Memory",
            "MCPSupport",
            .product(name: "ArgumentParser", package: "swift-argument-parser"),
        ]
    )
    let cliTestsTarget = Target.testTarget(
        name: "CLITests",
        dependencies: ["CLI"]
    )

    // ---------- CLI Command Tests ----------
    // (Removed: ServeTests and ChatTests had path/module issues with executable dependency.
    //  Re-add once CLI has testable library extraction.)

    // ---------- Test Support ----------

    let testSupportTarget = Target.target(
        name: "TestSupport",
        dependencies: []
    )

    return [
        // Foundation
        sharedTarget, sharedTestsTarget,
        loggingTarget, loggingTestsTarget,  // ClawLogging
        securityTarget, securityTestsTarget,
        storageTarget, storageTestsTarget,
        networkingTarget, networkingTestsTarget,
        // Protocols
        channelKitTarget, channelKitTestsTarget,
        providerKitTarget, providerKitTestsTarget,
        // Channels
        iMessageChannelTarget, iMessageChannelTestsTarget,
        whatsAppChannelTarget, whatsAppChannelTestsTarget,
        telegramChannelTarget, telegramChannelTestsTarget,
        slackChannelTarget, slackChannelTestsTarget,
        discordChannelTarget,
        signalChannelTarget,
        matrixChannelTarget,
        ircChannelTarget,
        webChatChannelTarget,
        // Providers
        claudeProviderTarget, claudeProviderTestsTarget,
        openAIProviderTarget, openAIProviderTestsTarget,
        ollamaProviderTarget,
        geminiProviderTarget,
        // Core
        gatewayTarget, gatewayTestsTarget,
        sessionsTarget, sessionsTestsTarget,
        agentsTarget,
        agentSpawnerTarget, agentSpawnerTestsTarget,
        schedulingTarget,
        voiceTarget, voiceTestsTarget,
        memoryTarget, memoryTestsTarget,
        mcpSupportTarget,
        // Services
        servicesTarget,
        // Executable
        cliTarget, cliTestsTarget,
        // Support
        testSupportTarget,
    ]
}()

// -------------------------------------------------------------

// MARK: Package

// -------------------------------------------------------------

let package = Package(
    name: "SwiftClaw",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: allProducts,
    dependencies: deps,
    targets: targets
)

// -------------------------------------------------------------

// MARK: Helper

// -------------------------------------------------------------

extension Product {
    static func singleTargetLibrary(_ name: String) -> Product {
        .library(name: name, targets: [name])
    }
}
