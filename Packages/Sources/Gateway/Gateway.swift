import Foundation
import Hummingbird
import HummingbirdWebSocket
import Shared
import IRelayLogging

// MARK: - Gateway Configuration

public struct GatewayConfiguration: Sendable {
    public var host: String
    public var port: Int
    public var authToken: String?

    public init(
        host: String = Defaults.gatewayHost,
        port: Int = Defaults.gatewayPort,
        authToken: String? = nil
    ) {
        self.host = host
        self.port = port
        self.authToken = authToken
    }
}

// MARK: - Gateway Server

public actor GatewayServer {
    private let config: GatewayConfiguration
    private let logger = Log.gateway
    private var webhookHandlers: [String: @Sendable (Data) async throws -> Data] = [:]

    public init(config: GatewayConfiguration = .init()) {
        self.config = config
    }

    /// Register a webhook handler for a path (e.g., "/webhooks/telegram").
    public func registerWebhook(
        path: String,
        handler: @escaping @Sendable (Data) async throws -> Data
    ) {
        webhookHandlers[path] = handler
        logger.info("Registered webhook: \(path)")
    }

    /// Build and return the Hummingbird application.
    public func buildApp() -> some ApplicationProtocol {
        let router = Router()
        let capturedLogger = logger
        let capturedConfig = config

        // Health check
        router.get("/health") { _, _ in
            return Response(status: .ok, body: .init(byteBuffer: .init(string: "{\"status\":\"ok\"}")))
        }

        // Status endpoint
        router.get("/status") { _, _ in
            let json = """
            {"version":"\(IRelayVersion.current)","status":"running"}
            """
            return Response(
                status: .ok,
                headers: [.contentType: "application/json"],
                body: .init(byteBuffer: .init(string: json))
            )
        }

        // Catch-all webhook endpoint: POST /webhooks/{service}
        let handlers = webhookHandlers
        router.post("/webhooks/{service}") { request, context in
            let service = context.parameters.get("service") ?? ""
            let webhookPath = "/webhooks/\(service)"
            guard let handler = handlers[webhookPath] else {
                return Response(status: .notFound)
            }
            let body = try await request.body.collect(upTo: 1_048_576)
            let data = Data(buffer: body)
            let responseData = try await handler(data)
            return Response(
                status: .ok,
                headers: [.contentType: "application/json"],
                body: .init(byteBuffer: .init(data: responseData))
            )
        }

        capturedLogger.info("Gateway configured on \(capturedConfig.host):\(capturedConfig.port)")

        let app = Application(
            router: router,
            configuration: .init(
                address: .hostname(capturedConfig.host, port: capturedConfig.port)
            )
        )

        return app
    }

    /// Start the gateway server (blocks until shutdown).
    public func run() async throws {
        logger.info("Starting gateway on \(config.host):\(config.port)")
        let app = buildApp()
        try await app.run()
    }
}
