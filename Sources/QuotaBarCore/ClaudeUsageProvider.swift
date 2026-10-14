import Foundation
import CryptoKit

protocol HTTPClient: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

final class URLSessionHTTPClient: HTTPClient, @unchecked Sendable {
    private let session = URLSession(configuration: .ephemeral)
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw ProviderError.invalidResponse("Claude")
        }
        return (data, response)
    }
}

public struct ClaudeCredential: Sendable {
    public let accessToken: String
    public let planHint: String?
    public let expiresAt: Date?
    public var sessionScope: String {
        "session-" + SHA256.hash(data: Data(accessToken.utf8)).prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    public init(accessToken: String, planHint: String?, expiresAt: Date? = nil) {
        self.accessToken = accessToken
        self.planHint = planHint
        self.expiresAt = expiresAt
    }
}

public struct ClaudeUsageProvider: UsageProvider {
    public let kind = ProviderKind.claude
    private let client: any HTTPClient
    private let credentialLoader: @Sendable () throws -> ClaudeCredential

    public init() {
        client = URLSessionHTTPClient()
        credentialLoader = { try ClaudeCredentialLoader.load() }
    }

    init(
        client: any HTTPClient = URLSessionHTTPClient(),
        credentialLoader: @escaping @Sendable () throws -> ClaudeCredential = { try ClaudeCredentialLoader.load() }
    ) {
        self.client = client
        self.credentialLoader = credentialLoader
    }

    public func fetch() async throws -> UsageSnapshot {
        let credential = try await Task.detached(priority: .utility) { try credentialLoader() }.value
        if let expires = credential.expiresAt, expires <= Date() {
            throw ProviderError.expiredCredentials("Claude")
        }
        guard let url = URL(string: "https://api.anthropic.com/api/oauth/usage") else {
            throw ProviderError.invalidResponse("Claude")
        }

        var request = URLRequest(url: url, timeoutInterval: 10)
        request.httpMethod = "GET"
        request.setValue("Bearer \(credential.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("QuotaBar/1.2.2", forHTTPHeaderField: "User-Agent")

        let (data, response): (Data, HTTPURLResponse)
        do {
            (data, response) = try await client.data(for: request)
        } catch let error as ProviderError {
            throw error
        } catch let error as URLError {
            if error.code == .timedOut { throw ProviderError.timedOut("Claude") }
            throw ProviderError.networkUnavailable("Claude")
        } catch {
            throw ProviderError.unavailable("Claude usage is currently unavailable.")
        }

        switch response.statusCode {
        case 200:
            let decoded = try ClaudeUsageDecoder.decode(data, planHint: credential.planHint, now: Date())
            return UsageSnapshot(provider: .claude, plan: decoded.plan, windows: decoded.windows,
                                 fetchedAt: decoded.fetchedAt, source: "Claude OAuth usage", account: nil, accountID: credential.sessionScope)
        case 401:
            throw ProviderError.notSignedIn("claude auth login")
        case 403:
            throw ProviderError.accessDenied("Claude")
        case 429:
            throw ProviderError.rateLimited("Claude")
        default:
            throw ProviderError.unavailable("Claude usage is currently unavailable.")
        }
    }
}

public enum ClaudeCredentialLoader {
    static func load() throws -> ClaudeCredential {
        if let credential = try? loadFromFile(), credential.expiresAt.map({ $0 > Date() }) ?? true { return credential }
        return try loadFromKeychain()
    }

    private static func loadFromKeychain() throws -> ClaudeCredential {
        let security = URL(fileURLWithPath: "/usr/bin/security")
        let result: ProcessResult
        do { result = try ProcessRunner.run(
            executable: security,
            arguments: ["find-generic-password", "-s", "Claude Code-credentials", "-w"],
            timeout: 8
        ) } catch ProcessRunnerError.timedOut { throw ProviderError.timedOut("Claude Keychain") }
        guard result.exitCode == 0 else {
            if result.exitCode == 44 { throw ProviderError.notSignedIn("claude auth login") }
            throw ProviderError.accessDenied("Claude Keychain")
        }
        return try decodeCredential(result.stdout)
    }

    private static func loadFromFile() throws -> ClaudeCredential {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/.credentials.json")
        let data = try Data(contentsOf: url)
        return try decodeCredential(data)
    }

    public static func decodeCredential(_ data: Data) throws -> ClaudeCredential {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderError.invalidResponse("Claude credentials")
        }
        let oauth = (root["claudeAiOauth"] as? [String: Any]) ?? root
        guard let token = (oauth["accessToken"] as? String) ?? (oauth["access_token"] as? String),
              !token.isEmpty else {
            throw ProviderError.notSignedIn("claude auth login")
        }
        let plan = (oauth["subscriptionType"] as? String)
            ?? (oauth["subscription_type"] as? String)
            ?? (oauth["rateLimitTier"] as? String)
            ?? (oauth["rate_limit_tier"] as? String)
        let expiry = (oauth["expiresAt"] as? NSNumber)?.doubleValue
        return ClaudeCredential(accessToken: token, planHint: plan.map(ClaudeUsageDecoder.prettyPlan),
                                expiresAt: expiry.map { Date(timeIntervalSince1970: $0 / 1000) })
    }
}

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
