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
        guard let previous else { return [] }
        let oldByID = Dictionary(uniqueKeysWithValues: previous.windows.map { ($0.id, $0) })
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
