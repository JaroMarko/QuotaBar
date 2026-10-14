import Foundation
import Darwin

/// Reads the minimal local measurement exported by Claude Code's session.usage().
/// No credentials, session identifiers, conversation content or network requests.
public struct ClaudeSessionUsageProvider: UsageProvider {
    public static let sourceName = "Claude Code session.usage"
    public let kind = ProviderKind.claude
    public let requiresNetwork = false
    public static let maximumBytes = 32_768
    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/QuotaBar/claude-session-usage.json")
    }
    private let url: URL

    public init(url: URL = Self.defaultURL) { self.url = url }

    public func fetch() async throws -> UsageSnapshot {
        let url = url
        return try await Task.detached(priority: .utility) { try Self.load(url: url) }.value
    }

    public static func load(url: URL = defaultURL, now: Date = Date()) throws -> UsageSnapshot {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            throw ProviderError.localBridgeUnavailable("Waiting for Claude Code usage. Enable the QuotaBar mod in a local Code session.")
        }
        defer { try? handle.close() }
        let data = try handle.read(upToCount: maximumBytes + 1) ?? Data()
        return try decode(data, now: now).snapshot
    }

    /// Validate before replacing the cache; encode only the allowlisted quota fields.
    public static func capture(data: Data, url: URL = defaultURL, now: Date = Date()) throws {
        let decoded = try decode(data, now: now, allowEmpty: true)
        let sanitized = try JSONEncoder().encode(decoded.envelope)
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Serialize independent mod instances so an older completed turn cannot replace newer usage.
        let lockURL = directory.appendingPathComponent(".claude-session-usage.lock")
        let descriptor = open(lockURL.path, O_CREAT | O_WRONLY | O_NOFOLLOW, mode_t(0o600))
        guard descriptor >= 0 else { throw ProviderError.unavailable("Cannot lock local Claude usage cache.") }
        defer { close(descriptor) }
        var locked = false
        for _ in 0..<50 {
            if flock(descriptor, LOCK_EX | LOCK_NB) == 0 { locked = true; break }
            guard errno == EWOULDBLOCK else { break }
            usleep(20_000)
        }
        guard locked else { throw ProviderError.unavailable("Cannot lock local Claude usage cache.") }
        defer { flock(descriptor, LOCK_UN) }
        if let handle = try? FileHandle(forReadingFrom: url) {
            defer { try? handle.close() }
            if let oldData = try? handle.read(upToCount: maximumBytes + 1),
               oldData.count <= maximumBytes,
               let old = try? JSONDecoder().decode(Envelope.self, from: oldData),
               old.version == 1, old.capturedAt.isFinite, old.capturedAt <= now.timeIntervalSince1970 + 5,
               old.capturedAt > decoded.envelope.capturedAt { return }
        }
        let temporary = directory.appendingPathComponent(".claude-usage-\(UUID().uuidString).tmp")
        guard FileManager.default.createFile(atPath: temporary.path, contents: sanitized,
                                            attributes: [.posixPermissions: 0o600]) else {
            throw ProviderError.unavailable("Cannot save local Claude Code usage.")
        }
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard rename(temporary.path, url.path) == 0 else {
            throw ProviderError.unavailable("Cannot replace local Claude Code usage.")
        }
    }

    private struct Envelope: Codable {
        let version: Int
        let capturedAt: Double
        let rateLimits: [Limit]
    }
    private struct Limit: Codable {
        let kind: String
        let percentUsed: Double
        let resetsAt: Double?
    }

    private static func decode(_ data: Data, now: Date, allowEmpty: Bool = false) throws -> (envelope: Envelope, snapshot: UsageSnapshot) {
        guard data.count <= maximumBytes,
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              envelope.version == 1, envelope.capturedAt.isFinite,
              envelope.capturedAt > 0, envelope.capturedAt <= now.timeIntervalSince1970 + 5,
              envelope.rateLimits.count <= 2 else {
            throw ProviderError.invalidResponse("Claude Code local usage")
        }
        let capturedAt = Date(timeIntervalSince1970: envelope.capturedAt)
        guard now.timeIntervalSince(capturedAt) <= 600 else {
            throw ProviderError.localBridgeUnavailable("Claude Code usage is outdated. Send a message in a local Code session to update it.")
        }
        var kinds = Set<String>()
        var windows: [UsageWindow] = []
        var validLimits: [Limit] = []
        for limit in envelope.rateLimits {
            guard ["five_hour", "seven_day"].contains(limit.kind),
                  kinds.insert(limit.kind).inserted,
                  limit.percentUsed.isFinite, (0...100).contains(limit.percentUsed),
                  limit.resetsAt.map({ $0.isFinite && $0 > 0 && $0 <= 253_402_300_799 }) ?? true else {
                throw ProviderError.invalidResponse("Claude Code local usage")
            }
            if let reset = limit.resetsAt, reset <= now.timeIntervalSince1970 { continue }
            validLimits.append(limit)
            windows.append(UsageWindow(id: "claude-\(limit.kind)",
                name: limit.kind == "five_hour" ? "5-hour session" : "Weekly",
                usedPercent: limit.percentUsed, resetsAt: limit.resetsAt.map { Date(timeIntervalSince1970: $0) },
                durationMinutes: limit.kind == "five_hour" ? 300 : 10_080))
        }
        guard !windows.isEmpty || allowEmpty else {
            throw ProviderError.localBridgeUnavailable("Waiting for current Claude Code quota windows. Send a message in a local Code session.")
        }
        windows.sort { ($0.durationMinutes ?? 0) < ($1.durationMinutes ?? 0) }
        let clean = Envelope(version: 1, capturedAt: envelope.capturedAt, rateLimits: validLimits)
        return (clean, UsageSnapshot(provider: .claude, plan: nil, windows: windows,
            fetchedAt: capturedAt, source: sourceName))
    }
}
