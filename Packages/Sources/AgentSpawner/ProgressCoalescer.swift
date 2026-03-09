import Foundation
import Shared

public actor ProgressCoalescer {
    private let interval: TimeInterval
    private var lastToolEmitTime: Date?

    public init(interval: TimeInterval = Defaults.Spawner.progressCoalesceInterval) {
        self.interval = interval
    }

    /// Returns the event if it should be emitted, or nil if suppressed.
    public func filter(_ event: AgentStreamEvent) -> AgentStreamEvent? {
        switch event {
        case .text, .done, .error:
            // Always pass through
            return event

        case .toolUse, .toolResult:
            let now = Date()
            if let lastTime = lastToolEmitTime,
               now.timeIntervalSince(lastTime) < interval
            {
                return nil
            }
            lastToolEmitTime = now
            return event

        case .progress:
            let now = Date()
            if let lastTime = lastToolEmitTime,
               now.timeIntervalSince(lastTime) < interval
            {
                return nil
            }
            lastToolEmitTime = now
            return event
        }
    }
}
