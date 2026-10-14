import Foundation

public enum ProviderKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case claude
    case codex

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        }
    }

    public var symbolName: String {
        switch self {
        case .claude: "sparkles"
        case .codex: "terminal.fill"
        }
    }
}

public struct UsageWindow: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let usedPercent: Double
    public let resetsAt: Date?
    public let durationMinutes: Int?

    public init(id: String, name: String, usedPercent: Double, resetsAt: Date?, durationMinutes: Int?) {
        self.id = id
        self.name = name
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
        self.durationMinutes = durationMinutes
    }

    public var clampedUsedPercent: Double {
        min(max(usedPercent, 0), 100)
    }

    public var remainingPercent: Double {
        100 - clampedUsedPercent
    }
}

public struct UsageSnapshot: Codable, Equatable, Sendable {
    public let provider: ProviderKind
    public let plan: String?
    public let windows: [UsageWindow]
    public let fetchedAt: Date

    public init(provider: ProviderKind, plan: String?, windows: [UsageWindow], fetchedAt: Date) {
        self.provider = provider
        self.plan = plan
        self.windows = windows
        self.fetchedAt = fetchedAt
    }

    public var highestUsedPercent: Double {
        windows.map(\.clampedUsedPercent).max() ?? 0
    }
}

public enum ProviderError: LocalizedError, Equatable, Sendable {
    case executableMissing(String)
    case notSignedIn(String)
    case timedOut(String)
    case rateLimited(String)
    case invalidResponse(String)
    case unavailable(String)

    public var errorDescription: String? {
        switch self {
        case let .executableMissing(name):
            "\(name) is not installed."
        case let .notSignedIn(name):
            "Sign in by running \(name) in Terminal."
        case let .timedOut(name):
            "\(name) did not respond in time."
        case let .rateLimited(name):
            "\(name) is temporarily rate limited."
        case let .invalidResponse(name):
            "\(name) returned usage data QuotaBar could not read."
        case let .unavailable(message):
            message
        }
    }
}

public protocol UsageProvider: Sendable {
    var kind: ProviderKind { get }
    func fetch() async throws -> UsageSnapshot
}

public struct ProviderDisplayState: Identifiable, Sendable {
    public let provider: ProviderKind
    public var snapshot: UsageSnapshot?
    public var errorMessage: String?
    public var isRefreshing: Bool
    public var isStale: Bool

    public init(provider: ProviderKind, snapshot: UsageSnapshot?, errorMessage: String?, isRefreshing: Bool, isStale: Bool) {
        self.provider = provider
        self.snapshot = snapshot
        self.errorMessage = errorMessage
        self.isRefreshing = isRefreshing
        self.isStale = isStale
    }

    public var id: ProviderKind { provider }
}

public enum UsageFormatting {
    public static func percent(_ value: Double) -> String {
        String(format: "%.0f%%", value)
    }

    public static func countdown(to date: Date?, now: Date = Date()) -> String {
        guard let date else { return "Reset time unavailable" }
        let remaining = max(0, Int(date.timeIntervalSince(now)))
        if remaining == 0 { return "Resetting now" }

        let days = remaining / 86_400
        let hours = (remaining % 86_400) / 3_600
        let minutes = (remaining % 3_600) / 60

        if days > 0 { return "Resets in \(days)d \(hours)h" }
        if hours > 0 { return "Resets in \(hours)h \(minutes)m" }
        return "Resets in \(max(1, minutes))m"
    }
}
