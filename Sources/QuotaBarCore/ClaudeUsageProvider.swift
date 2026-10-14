import Foundation

// Decode server-reported subscription utilization and reset windows for the OAuth fallback.
public enum ClaudeUsageDecoder {
    private static let preferredKeys = [
        "five_hour", "seven_day", "seven_day_sonnet", "seven_day_opus",
        "seven_day_routines", "seven_day_cowork"
    ]

    public static func decode(_ data: Data, planHint: String?, now: Date) throws -> UsageSnapshot {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderError.invalidResponse("Claude")
        }

        let responsePlan = (root["subscription_type"] as? String)
            ?? (root["subscriptionType"] as? String)
            ?? (root["rate_limit_tier"] as? String)
        let plan = responsePlan.map(prettyPlan) ?? planHint
        var windows: [UsageWindow] = []

        let additionalKeys = root.keys.filter { !preferredKeys.contains($0) && ($0.hasPrefix("seven_day_") || $0.hasPrefix("five_hour_")) }.sorted()
        for key in preferredKeys + additionalKeys {
            guard let item = root[key] as? [String: Any], let window = decodeWindow(item, key: key) else { continue }
            windows.append(window)
        }

        if let scoped = root["limits"] as? [[String: Any]] {
            for (index, item) in scoped.enumerated() {
                guard let window = decodeScopedWindow(item, index: index) else { continue }
                if !windows.contains(where: { $0.id == window.id }) { windows.append(window) }
            }
        }

        guard !windows.isEmpty else { throw ProviderError.invalidResponse("Claude") }
        return UsageSnapshot(provider: .claude, plan: plan, windows: windows, fetchedAt: now)
    }

    public static func prettyPlan(_ raw: String) -> String {
        let lower = raw.lowercased()
        if lower.contains("max_20x") || lower.contains("max 20x") { return "Max 20x" }
        if lower.contains("max_5x") || lower.contains("max 5x") { return "Max 5x" }
        if lower.contains("enterprise") { return "Enterprise" }
        if lower.contains("team") { return "Team" }
        if lower.contains("max") { return "Max" }
        if lower.contains("pro") { return "Pro" }
        return raw.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private static func decodeWindow(_ item: [String: Any], key: String) -> UsageWindow? {
        guard let utilization = number(item["utilization"] ?? item["used_percent"] ?? item["usedPercent"]) else {
            return nil
        }
        return UsageWindow(
            id: "claude-\(key)",
            name: displayName(for: key),
            usedPercent: utilization,
            resetsAt: parseDate(item["resets_at"] ?? item["resetsAt"]),
            durationMinutes: duration(for: key)
        )
    }

    private static func decodeScopedWindow(_ item: [String: Any], index: Int) -> UsageWindow? {
        let nested = (item["weekly_scoped"] as? [String: Any]) ?? item
        guard let utilization = number(nested["utilization"] ?? nested["used_percent"] ?? nested["usedPercent"]) else {
            return nil
        }
        let rawName = (item["display_name"] as? String)
            ?? (item["name"] as? String)
            ?? (item["model"] as? String)
            ?? "Model \(index + 1)"
        let slug = rawName.lowercased().replacingOccurrences(of: " ", with: "-")
        return UsageWindow(
            id: "claude-weekly-scoped-\(slug)",
            name: "\(rawName) weekly",
            usedPercent: utilization,
            resetsAt: parseDate(nested["resets_at"] ?? nested["resetsAt"]),
            durationMinutes: 10_080
        )
    }

    private static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue.isFinite ? number.doubleValue : nil }
        if let string = value as? String, let number = Double(string), number.isFinite { return number }
        return nil
    }

    private static func parseDate(_ value: Any?) -> Date? {
        if let number = value as? NSNumber { return number.doubleValue.isFinite ? Date(timeIntervalSince1970: number.doubleValue) : nil }
        guard let string = value as? String else { return nil }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return withFraction.date(from: string) ?? ISO8601DateFormatter().date(from: string)
    }

    private static func duration(for key: String) -> Int? {
        if key == "five_hour" { return 300 }
        if key.hasPrefix("seven_day") { return 10_080 }
        return nil
    }

    private static func displayName(for key: String) -> String {
        switch key {
        case "five_hour": "5-hour session"
        case "seven_day": "Weekly"
        case "seven_day_sonnet": "Sonnet weekly"
        case "seven_day_opus": "Opus weekly"
        case "seven_day_routines": "Routines weekly"
        case "seven_day_cowork": "Cowork weekly"
        default: key.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}
