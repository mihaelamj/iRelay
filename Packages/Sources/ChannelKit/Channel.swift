// ChannelKit — Channel protocol + registry
import Shared

public protocol Channel: Actor {
    var id: String { get }
    var status: ChannelStatus { get }
    func start() async throws
    func stop() async throws
    func send(_ message: OutboundMessage) async throws
    func onMessage(_ handler: @escaping @Sendable (InboundMessage) async -> Void)
}

public enum ChannelStatus: Sendable, Equatable {
    case disconnected
    case connecting
    case connected
    case error(String)
}
