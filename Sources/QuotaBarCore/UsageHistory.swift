import Foundation

public struct UsageSample: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let provider: ProviderKind
    public let accountScope: String
    public let windowID: String
    public let measuredAt: Date
    public let usedPercent: Double
    public let resetsAt: Date?
    public let durationMinutes: Int?

    public init(provider: ProviderKind, accountScope: String, window: UsageWindow, measuredAt: Date) {
        id = UUID(); self.provider = provider; self.accountScope = accountScope
        windowID = window.id; self.measuredAt = measuredAt
        usedPercent = window.clampedUsedPercent; resetsAt = window.resetsAt
        durationMinutes = window.durationMinutes
    }
}

public struct UsageHistory: Codable, Sendable {
    public private(set) var samples: [UsageSample] = []
    public init() {}

    public mutating func append(_ snapshot: UsageSnapshot, maximumSamples: Int = 10_000, retentionDays: Int = 30) {
        for window in snapshot.windows where window.usedPercent.isFinite {
            // Manual refresh can produce identical timestamps; don't duplicate.
            if samples.contains(where: { $0.provider == snapshot.provider && $0.accountScope == snapshot.accountScope
                && $0.windowID == window.id && $0.measuredAt == snapshot.fetchedAt }) { continue }
            samples.append(UsageSample(provider: snapshot.provider, accountScope: snapshot.accountScope,
                                       window: window, measuredAt: snapshot.fetchedAt))
        }
        prune(now: snapshot.fetchedAt, maximumSamples: maximumSamples, retentionDays: retentionDays)
    }

    public mutating func prune(now: Date, maximumSamples: Int = 10_000, retentionDays: Int = 30) {
        let cutoff = now.addingTimeInterval(-Double(max(1, retentionDays)) * 86_400)
        samples = Array(samples.filter { $0.measuredAt >= cutoff && $0.measuredAt <= now && $0.usedPercent.isFinite }
            .sorted { $0.measuredAt < $1.measuredAt }.suffix(max(0, maximumSamples)))
    }

    public func series(for snapshot: UsageSnapshot, window: UsageWindow) -> [UsageSample] {
        samples.filter { $0.provider == snapshot.provider && $0.accountScope == snapshot.accountScope
            && $0.windowID == window.id && $0.resetsAt == window.resetsAt }
            .sorted { $0.measuredAt < $1.measuredAt }
    }
}

public struct UsageForecast: Sendable {
    public let percentPerHour: Double
    public let estimatedExhaustion: Date?

    public static func estimate(samples: [UsageSample], now: Date) -> UsageForecast? {
        let recent = samples.filter { now.timeIntervalSince($0.measuredAt) <= 3600 && $0.measuredAt <= now }
            .sorted { $0.measuredAt < $1.measuredAt }
        guard recent.count >= 3, let first = recent.first, let last = recent.last,
              last.accountScope != "unknown", now.timeIntervalSince(last.measuredAt) <= 600,
              let reset = last.resetsAt, reset > now,
              last.measuredAt.timeIntervalSince(first.measuredAt) >= 600,
              recent.allSatisfy({ $0.provider == last.provider && $0.accountScope == last.accountScope
                  && $0.windowID == last.windowID && $0.resetsAt == reset }) else { return nil }
        for pair in zip(recent, recent.dropFirst()) {
            if pair.1.usedPercent < pair.0.usedPercent || pair.1.measuredAt <= pair.0.measuredAt { return nil }
        }
        let rate = (last.usedPercent - first.usedPercent) / last.measuredAt.timeIntervalSince(first.measuredAt)
        guard rate.isFinite, rate > 0, last.usedPercent < 100 else { return nil }
        let exhaustion = last.measuredAt.addingTimeInterval((100 - last.usedPercent) / rate)
        // If extrapolation says we have already exhausted without a fresh
        // confirming measurement, suppress the stale prediction.
        guard exhaustion > now else { return nil }
        return UsageForecast(percentPerHour: rate * 3600, estimatedExhaustion: exhaustion < reset ? exhaustion : nil)
    }

    public static func evenUsePercent(window: UsageWindow, at date: Date) -> Double? {
        guard let reset = window.resetsAt, let minutes = window.durationMinutes, minutes > 0 else { return nil }
        let duration = Double(minutes) * 60
        return min(100, max(0, 100 * (1 - reset.timeIntervalSince(date) / duration)))
    }
}
