import Foundation

public enum RefreshPolicy {
    public static func interval(previous: UsageSnapshot?, current: UsageSnapshot, now: Date) -> TimeInterval {
        let nearReset = current.windows.contains { window in
            guard let reset = window.resetsAt else { return false }
            return reset.timeIntervalSince(now) < 300
        }
        let changed: Bool
        if let previous, previous.accountScope == current.accountScope {
            changed = current.windows.contains { window in
                guard let old = previous.windows.first(where: { $0.id == window.id }) else { return true }
                return abs(old.clampedUsedPercent - window.clampedUsedPercent) >= 0.5
                    || old.resetsAt != window.resetsAt
            }
        } else { changed = true }
        return nearReset || changed || current.highestUsedPercent >= 90 ? 60 : 300
    }

    public static func retryInterval(failures: Int, error: ProviderError?) -> TimeInterval {
        switch error {
        case .rateLimited: return 600
        case .notSignedIn, .expiredCredentials, .accessDenied, .executableMissing: return 900
        default: return min(900, 60 * pow(2, Double(min(4, max(0, failures - 1)))))
        }
    }
}
