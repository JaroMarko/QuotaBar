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
    public let source: String?
    public let account: String?
    public let accountID: String?

    public init(provider: ProviderKind, plan: String?, windows: [UsageWindow], fetchedAt: Date, source: String? = nil, account: String? = nil, accountID: String? = nil) {
        self.provider = provider
        self.plan = plan
        self.windows = windows
        self.fetchedAt = fetchedAt
        self.source = source
        self.account = account
        self.accountID = accountID
    }

    public var accountScope: String { accountID ?? account ?? "unknown" }

    /// Highest usage across all reported windows, used by refresh policy.
    public var mostUsedWindow: UsageWindow? {
        windows.lazy.filter { $0.usedPercent.isFinite }
            .max { $0.clampedUsedPercent < $1.clampedUsedPercent }
    }

    /// Claude always shows its shared 5-hour session; never substitute weekly.
    public var meterWindow: UsageWindow? {
        if provider == .claude {
            return windows.first { $0.id == "claude-five_hour" && $0.usedPercent.isFinite }
        }
        return mostUsedWindow
    }

    public var highestUsedPercent: Double { mostUsedWindow?.clampedUsedPercent ?? 0 }
}

public enum ProviderError: LocalizedError, Equatable, Sendable {
    case executableMissing(String)
    case notSignedIn(String)
    case timedOut(String)
    case rateLimited(String)
    case invalidResponse(String)
    case unavailable(String)
    case networkUnavailable(String)
    case accessDenied(String)
    case expiredCredentials(String)

    public var recoveryExplanation: String {
        switch self {
        case .rateLimited:
            "The provider temporarily rejected requests to read usage (HTTP 429). This does not by itself mean your subscription quota is exhausted. QuotaBar pauses checks for 10 minutes, then retries automatically. The provider may continue limiting requests after that. Shown percentages are last known values. Refresh and restarting QuotaBar do not bypass this pause."
        case .networkUnavailable:
            "Usage could not be checked because the network is unavailable. Last known values are retained; QuotaBar retries when connectivity recovers."
        case .notSignedIn, .expiredCredentials:
            "Sign in again using the provider's official CLI. QuotaBar reads that existing login and does not store your password."
        case .accessDenied:
            "The provider refused access. Check your provider subscription and any macOS Keychain permission prompt."
        case .executableMissing:
            "Install the provider's official CLI and sign in before refreshing."
        case .timedOut:
            "The provider took too long to respond. QuotaBar keeps the last known values and retries automatically."
        case .invalidResponse:
            "The provider returned data QuotaBar could not read. This does not confirm a zero or exhausted quota."
        case .unavailable:
            "A current measurement is unavailable. Last known values, if present, may be outdated. QuotaBar will retry automatically."
        }
    }

    public var errorDescription: String? {
        switch self {
        case let .executableMissing(name):
            "\(name) is not installed."
        case let .notSignedIn(name):
            "Sign in by running \(name) in Terminal."
        case let .timedOut(name):
            "\(name) did not respond in time."
        case let .rateLimited(name):
            "\(name) is temporarily limiting quota checks."
        case let .invalidResponse(name):
            "\(name) returned usage data QuotaBar could not read."
        case let .networkUnavailable(name):
            "\(name): network unavailable. Last known data is retained."
        case let .accessDenied(name):
            "\(name): access denied. Check Keychain permissions and your plan."
        case let .expiredCredentials(name):
            "\(name): login expired. Sign in again with the official CLI."
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
    public var errorHelp: String?
    public var isRefreshing: Bool
    public var isStale: Bool

    public init(provider: ProviderKind, snapshot: UsageSnapshot?, errorMessage: String?, isRefreshing: Bool, isStale: Bool, errorHelp: String? = nil) {
        self.provider = provider
        self.snapshot = snapshot
        self.errorMessage = errorMessage
        self.errorHelp = errorHelp
        self.isRefreshing = isRefreshing
        self.isStale = isStale
    }

    public var id: ProviderKind { provider }

    public func hasStaleData(at now: Date = Date()) -> Bool {
        guard let snapshot else { return false }
        return isStale || now.timeIntervalSince(snapshot.fetchedAt) > 600
            || snapshot.windows.contains { $0.resetsAt.map { $0 <= now } ?? false }
    }

    public func meterValue(at now: Date = Date()) -> Double? {
        guard let snapshot, !hasStaleData(at: now) else { return nil }
        return snapshot.meterWindow?.clampedUsedPercent
    }
}

public enum UsageFormatting {
    public static func percent(_ value: Double) -> String {
        String(format: "%.0f%%", value)
    }

    public static func countdown(to date: Date?, now: Date = Date()) -> String {
        guard let date else { return "Reset time unavailable" }
        let remaining = max(0, Int(date.timeIntervalSince(now)))
        if remaining == 0 { return "Awaiting reset confirmation" }

        let days = remaining / 86_400
        let hours = (remaining % 86_400) / 3_600
        let minutes = (remaining % 3_600) / 60

        if days > 0 { return "Resets in \(days)d \(hours)h" }
        if hours > 0 { return "Resets in \(hours)h \(minutes)m" }
        return "Resets in \(max(1, minutes))m"
    }
}
