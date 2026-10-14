import Foundation

public enum AlertKind: String, Equatable, Sendable {
    case threshold
    case reset
}

public struct UsageAlert: Equatable, Sendable {
    public let kind: AlertKind
    public let provider: ProviderKind
    public let windowName: String
    public let threshold: Int?

    public init(kind: AlertKind, provider: ProviderKind, windowName: String, threshold: Int?) {
        self.kind = kind
        self.provider = provider
        self.windowName = windowName
        self.threshold = threshold
    }
}

public enum AlertEngine {
    public static func events(
        previous: UsageSnapshot?,
        current: UsageSnapshot,
        enabledThresholds: [Int],
        resetEnabled: Bool
    ) -> [UsageAlert] {
        guard let previous, previous.provider == current.provider, previous.accountScope == current.accountScope else { return [] }
        let oldByID = Dictionary(previous.windows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var events: [UsageAlert] = []

        for window in current.windows {
            guard let old = oldByID[window.id] else { continue }
            for threshold in enabledThresholds.sorted() where
                old.clampedUsedPercent < Double(threshold)
                && window.clampedUsedPercent >= Double(threshold) {
                events.append(UsageAlert(
                    kind: .threshold,
                    provider: current.provider,
                    windowName: window.name,
                    threshold: threshold
                ))
            }

            if resetEnabled,
               let oldReset = old.resetsAt,
               let newReset = window.resetsAt,
               newReset > oldReset,
               window.clampedUsedPercent < old.clampedUsedPercent {
                events.append(UsageAlert(
                    kind: .reset,
                    provider: current.provider,
                    windowName: window.name,
                    threshold: nil
                ))
            }
        }
        return events
    }
}

// Persist only notification keys/times. No credentials or conversation content.
public struct AlertLedger: Codable, Sendable {
    private var delivered: [String: Date] = [:]
    public init() {}

    public mutating func take(previous: UsageSnapshot?, current: UsageSnapshot,
                              thresholds: [Int], resetEnabled: Bool) -> [UsageAlert] {
        let events = AlertEngine.events(previous: previous, current: current,
                                        enabledThresholds: thresholds, resetEnabled: resetEnabled)
        var accepted: [UsageAlert] = []
        for event in events {
            guard let window = current.windows.first(where: { $0.name == event.windowName }) else { continue }
            // Without a reset identity, a threshold is emitted at most once per
            // account/window instead of rearming on fluctuating measurements.
            let cycle = window.resetsAt.map { String(Int($0.timeIntervalSince1970)) } ?? "unknown-cycle"
            let key = [current.provider.rawValue, current.accountScope, window.id, cycle,
                       event.kind.rawValue, String(event.threshold ?? -1)].joined(separator: "|")
            if delivered[key] == nil { delivered[key] = current.fetchedAt; accepted.append(event) }
        }
        delivered = delivered.filter { current.fetchedAt.timeIntervalSince($0.value) < 60 * 86_400 }
        if delivered.count > 512 {
            delivered = Dictionary(uniqueKeysWithValues: delivered.sorted { $0.value > $1.value }.prefix(512).map { ($0.key, $0.value) })
        }
        return accepted
    }
}
