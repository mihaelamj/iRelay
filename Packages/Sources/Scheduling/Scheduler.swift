import Foundation
import Shared
import IRelayLogging

// MARK: - Scheduled Task

public struct ScheduledTask: Sendable, Identifiable {
    public let id: String
    public let name: String
    public let schedule: Schedule
    public let action: @Sendable () async throws -> Void

    public init(id: String, name: String, schedule: Schedule, action: @escaping @Sendable () async throws -> Void) {
        self.id = id
        self.name = name
        self.schedule = schedule
        self.action = action
    }
}

// MARK: - Schedule

public enum Schedule: Sendable {
    case interval(TimeInterval)         // Every N seconds
    case daily(hour: Int, minute: Int)  // Daily at HH:MM
    case cron(String)                   // Cron expression (parsed at runtime)

    /// Calculate the next fire date from now.
    public func nextFire(from now: Date = .now) -> Date {
        switch self {
        case .interval(let seconds):
            return now.addingTimeInterval(seconds)

        case .daily(let hour, let minute):
            let calendar = Calendar.current
            var components = calendar.dateComponents([.year, .month, .day], from: now)
            components.hour = hour
            components.minute = minute
            components.second = 0
            guard let candidate = calendar.date(from: components) else {
                return now.addingTimeInterval(86400)
            }
            return candidate > now ? candidate : candidate.addingTimeInterval(86400)

        case .cron:
            // Simplified: treat as hourly for now
            // Full cron parsing can be added later
            return now.addingTimeInterval(3600)
        }
    }
}

// MARK: - Scheduler

public actor Scheduler {
    private var tasks: [String: ScheduledTask] = [:]
    private var timers: [String: Task<Void, Never>] = [:]
    private var isRunning = false
    private let logger = Log.scheduler

    public init() {}

    /// Register a scheduled task.
    public func register(_ task: ScheduledTask) {
        tasks[task.id] = task
        logger.info("Registered task: \(task.name) (\(task.id))")
    }

    /// Start all scheduled tasks.
    public func start() {
        guard !isRunning else { return }
        isRunning = true

        for (id, task) in tasks {
            startTimer(for: id, task: task)
        }
        logger.info("Scheduler started with \(tasks.count) tasks")
    }

    /// Stop all scheduled tasks.
    public func stop() {
        isRunning = false
        for timer in timers.values {
            timer.cancel()
        }
        timers.removeAll()
        logger.info("Scheduler stopped")
    }

    /// Remove a task.
    public func remove(_ taskID: String) {
        tasks.removeValue(forKey: taskID)
        timers[taskID]?.cancel()
        timers.removeValue(forKey: taskID)
    }

    /// List all registered task IDs.
    public var registeredIDs: [String] {
        Array(tasks.keys)
    }

    // MARK: - Timer Management

    private func startTimer(for id: String, task: ScheduledTask) {
        let timer = Task {
            while !Task.isCancelled {
                let nextFire = task.schedule.nextFire()
                let delay = nextFire.timeIntervalSinceNow
                guard delay > 0 else { continue }

                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { break }

                do {
                    try await task.action()
                    logger.debug("Task \(task.name) completed")
                } catch {
                    logger.warning("Task \(task.name) failed: \(error)")
                }
            }
        }
        timers[id] = timer
    }
}
