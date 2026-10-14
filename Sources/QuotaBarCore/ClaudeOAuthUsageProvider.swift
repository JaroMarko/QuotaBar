import Foundation
import CryptoKit

public struct ClaudeOAuthFailure: Error, Sendable {
    public let error: ProviderError
    public let nextRetryDate: Date?
    public init(error: ProviderError, nextRetryDate: Date? = nil) {
        self.error = error
        self.nextRetryDate = nextRetryDate
    }
}

protocol HTTPClient: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

final class URLSessionHTTPClient: HTTPClient, @unchecked Sendable {
    private let session: URLSession
    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 10
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        session = URLSession(configuration: configuration)
    }
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw ProviderError.invalidResponse("Claude")
        }
        guard response.statusCode == 200 else { return (Data(), response) }
        guard response.expectedContentLength <= 1_048_576 else {
            throw ProviderError.invalidResponse("Claude")
        }
        var data = Data()
        for try await byte in bytes {
            guard data.count < 1_048_576 else { throw ProviderError.invalidResponse("Claude") }
            data.append(byte)
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

public struct ClaudeOAuthUsageProvider: UsageProvider {
    public static let sourceName = "Claude OAuth fallback"
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
        request.setValue("QuotaBar/1.5.0", forHTTPHeaderField: "User-Agent")

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
                                 fetchedAt: decoded.fetchedAt, source: Self.sourceName, account: nil, accountID: credential.sessionScope)
        case 401:
            throw ProviderError.notSignedIn("claude auth login")
        case 403:
            throw ProviderError.accessDenied("Claude")
        case 429:
            throw ClaudeOAuthFailure(error: .rateLimited("Claude"), nextRetryDate: Self.retryAfter(response.value(forHTTPHeaderField: "Retry-After")))
        default:
            throw ProviderError.unavailable("Claude usage is currently unavailable.")
        }
    }
    public static func retryAfter(_ value: String?, now: Date = Date()) -> Date? {
        guard let value else { return nil }
        if let seconds = Double(value.trimmingCharacters(in: .whitespaces)), seconds.isFinite, seconds >= 0 {
            return now.addingTimeInterval(seconds)
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss z"
        return formatter.date(from: value)
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
