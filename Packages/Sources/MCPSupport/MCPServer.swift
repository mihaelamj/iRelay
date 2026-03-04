import Foundation
import Shared
import ClawLogging

// MARK: - MCP Tool

public struct MCPTool: Sendable, Codable {
    public let name: String
    public let description: String
    public let inputSchema: String // JSON Schema

    public init(name: String, description: String, inputSchema: String) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
    }
}

// MARK: - MCP Server Configuration

public struct MCPServerConfig: Sendable, Codable {
    public var name: String
    public var command: String
    public var args: [String]
    public var env: [String: String]
    public var isEnabled: Bool

    public init(name: String, command: String, args: [String] = [], env: [String: String] = [:], isEnabled: Bool = true) {
        self.name = name
        self.command = command
        self.args = args
        self.env = env
        self.isEnabled = isEnabled
    }
}

// MARK: - MCP Client

/// Manages connections to external MCP tool servers via stdio.
public actor MCPClient {
    private let config: MCPServerConfig
    private var process: Process?
    private var stdin: FileHandle?
    private var stdout: FileHandle?
    private var requestID: Int = 0
    private let logger = Log.logger(for: "mcp")

    public init(config: MCPServerConfig) {
        self.config = config
    }

    /// Start the MCP server subprocess.
    public func start() throws {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: config.command)
        proc.arguments = config.args
        proc.environment = ProcessInfo.processInfo.environment.merging(config.env) { _, new in new }

        let inPipe = Pipe()
        let outPipe = Pipe()
        proc.standardInput = inPipe
        proc.standardOutput = outPipe
        proc.standardError = Pipe()

        try proc.run()
        self.process = proc
        self.stdin = inPipe.fileHandleForWriting
        self.stdout = outPipe.fileHandleForReading

        logger.info("MCP server started: \(config.name) (\(config.command))")
    }

    /// Stop the MCP server.
    public func stop() {
        process?.terminate()
        process = nil
        stdin = nil
        stdout = nil
        logger.info("MCP server stopped: \(config.name)")
    }

    /// List available tools from the MCP server.
    public func listTools() async throws -> [MCPTool] {
        let response = try await sendRequest(method: "tools/list", params: [:])
        guard let tools = response["tools"] as? [[String: Any]] else { return [] }

        return tools.compactMap { dict in
            guard let name = dict["name"] as? String,
                  let description = dict["description"] as? String else { return nil }
            let schema = (dict["inputSchema"] as? [String: Any]).flatMap { try? JSONSerialization.data(withJSONObject: $0) }
            return MCPTool(
                name: name,
                description: description,
                inputSchema: schema.flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
            )
        }
    }

    /// Call a tool on the MCP server.
    public func callTool(name: String, argumentsJSON: String) async throws -> String {
        let args = (try? JSONSerialization.jsonObject(with: Data(argumentsJSON.utf8))) ?? [:]
        let response = try await sendRequest(method: "tools/call", params: [
            "name": name,
            "arguments": args,
        ])

        if let content = response["content"] as? [[String: Any]],
           let first = content.first,
           let text = first["text"] as? String {
            return text
        }

        let data = try JSONSerialization.data(withJSONObject: response)
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    // MARK: - JSON-RPC

    private func sendRequest(method: String, params: [String: Any]) async throws -> [String: Any] {
        requestID += 1
        let request: [String: Any] = [
            "jsonrpc": "2.0",
            "id": requestID,
            "method": method,
            "params": params,
        ]

        let data = try JSONSerialization.data(withJSONObject: request)
        guard let stdin else {
            throw SwiftClawError.connectionFailed("MCP server not running: \(config.name)")
        }

        // Write JSON-RPC message with Content-Length header
        let header = "Content-Length: \(data.count)\r\n\r\n"
        stdin.write(Data(header.utf8))
        stdin.write(data)

        // Read response
        guard let stdout else {
            throw SwiftClawError.connectionFailed("MCP server not running: \(config.name)")
        }

        // Read Content-Length header (read until \r\n\r\n)
        var headerStr = ""
        let separator = "\r\n\r\n"
        while !headerStr.hasSuffix(separator) {
            let byte = stdout.readData(ofLength: 1)
            guard let ch = String(data: byte, encoding: .utf8) else { continue }
            headerStr += ch
        }

        let lengthStr = headerStr.components(separatedBy: ":").last?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "0"
        let length = Int(lengthStr) ?? 0

        let responseData = stdout.readData(ofLength: length)
        guard let json = try JSONSerialization.jsonObject(with: responseData) as? [String: Any] else {
            throw SwiftClawError.protocolError("Invalid MCP response")
        }

        if let error = json["error"] as? [String: Any], let message = error["message"] as? String {
            throw SwiftClawError.toolCallFailed(toolName: method, reason: message)
        }

        return json["result"] as? [String: Any] ?? [:]
    }
}

// MARK: - MCP Registry

/// Manages multiple MCP server connections.
public actor MCPRegistry {
    private var clients: [String: MCPClient] = [:]
    private let logger = Log.logger(for: "mcp")

    public init() {}

    /// Add and start an MCP server.
    public func add(_ config: MCPServerConfig) async throws {
        let client = MCPClient(config: config)
        try await client.start()
        clients[config.name] = client
        logger.info("MCP server registered: \(config.name)")
    }

    /// Get all available tools across all servers.
    public func allTools() async throws -> [(server: String, tool: MCPTool)] {
        var result: [(String, MCPTool)] = []
        for (name, client) in clients {
            let tools = try await client.listTools()
            result.append(contentsOf: tools.map { (name, $0) })
        }
        return result
    }

    /// Call a tool by name, finding the right server automatically.
    public func callTool(name: String, argumentsJSON: String) async throws -> String {
        for (_, client) in clients {
            let tools = try await client.listTools()
            if tools.contains(where: { $0.name == name }) {
                return try await client.callTool(name: name, argumentsJSON: argumentsJSON)
            }
        }
        throw SwiftClawError.toolCallFailed(toolName: name, reason: "No MCP server provides this tool")
    }

    /// Stop all servers.
    public func stopAll() async {
        for client in clients.values {
            await client.stop()
        }
        clients.removeAll()
    }
}
