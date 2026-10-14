import Foundation

/// Local Code observations first; experimental read-only OAuth only when needed.
/// Own retry state lets new local observations arrive during an API cooldown.
public actor ClaudeHybridUsageProvider: UsageProvider {
    public nonisolated let kind = ProviderKind.claude
    public nonisolated let requiresNetwork = false
    public static let localFreshness: TimeInterval = 300
    private let fetchLocal: @Sendable () throws -> UsageSnapshot
    private let fetchOAuth: @Sendable () async throws -> UsageSnapshot
    private let now: @Sendable () -> Date
    private let defaults: UserDefaults
    private var persisted: Persisted
    private var inFlight: Task<UsageSnapshot, Error>?
    private struct Persisted: Codable {
        var apiSnapshot: UsageSnapshot?
        var nextAttempt: Date?
        var rateLimitCount = 0
        var failure: String?
    }
    private static let persistenceKey = "claude.hybrid.retry-state.v1"

    public init(
        defaults: UserDefaults = .standard,
        fetchLocal: @escaping @Sendable () throws -> UsageSnapshot = { try ClaudeSessionUsageProvider.load() },
        fetchOAuth: @escaping @Sendable () async throws -> UsageSnapshot = { try await ClaudeOAuthUsageProvider().fetch() },
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.defaults = defaults
        self.fetchLocal = fetchLocal
        self.fetchOAuth = fetchOAuth
        self.now = now
        if let data = defaults.data(forKey: Self.persistenceKey),
           data.count <= 1_048_576,
           let state = try? JSONDecoder().decode(Persisted.self, from: data) {
            persisted = state
        } else { persisted = Persisted() }
    }

    public nonisolated static func supports(_ snapshot: UsageSnapshot) -> Bool {
        snapshot.provider == .claude && [ClaudeSessionUsageProvider.sourceName, ClaudeOAuthUsageProvider.sourceName].contains(snapshot.source ?? "")
    }

    public func fetch() async throws -> UsageSnapshot {
        let date = now()
        let local = (try? fetchLocal()).flatMap { valid($0, at: date) }
        let api = persisted.apiSnapshot.flatMap { valid($0, at: date) }
        // Do not regress from a newer API observation to an older local one.
        if let local, local.meterWindow != nil, date.timeIntervalSince(local.fetchedAt) <= Self.localFreshness {
            return newest(local, api)!.withNotice(nil)
        }
        if let api, api.meterWindow != nil, date.timeIntervalSince(api.fetchedAt) <= 600,
           api.fetchedAt >= (local?.fetchedAt ?? .distantPast), persisted.failure == nil {
            return api.withNotice(nil)
        }
        if let task = inFlight {
            // The initiating fetch owns bookkeeping; another caller only awaits its result.
            let completed = try? await task.value
            let latest = (try? fetchLocal()).flatMap { valid($0, at: now()) }
            let completedAPI = completed.flatMap { valid($0, at: now()) }
            if let snapshot = newest(latest, newest(completedAPI, persisted.apiSnapshot.flatMap { valid($0, at: now()) })) {
                let freshLocal = latest.map { $0.meterWindow != nil && now().timeIntervalSince($0.fetchedAt) <= Self.localFreshness } ?? false
                return snapshot.withNotice(freshLocal ? nil : pauseNotice(at: now()))
            }
            throw ProviderError.unavailable(pauseNotice(at: now()) ?? "Waiting for Claude usage from Code or the API fallback.")
        }
        if let deadline = persisted.nextAttempt, deadline > date {
            if let snapshot = newest(local, api) { return snapshot.withNotice(pauseNotice(at: date)) }
            throw ProviderError.unavailable(pauseNotice(at: date) ?? "Waiting for Claude API fallback retry.")
        }
        // Persist before awaiting, so restart or reentrancy cannot bypass spacing.
        persisted.nextAttempt = date.addingTimeInterval(300)
        save()
        let fetch = fetchOAuth
        let task = Task { try await fetch() }
        inFlight = task
        do {
            let raw = try await task.value
            guard Self.supports(raw), let snapshot = valid(raw, at: now()) else {
                throw ProviderError.invalidResponse("Claude OAuth fallback")
            }
            persisted.apiSnapshot = snapshot.withNotice(nil)
            persisted.rateLimitCount = 0
            persisted.failure = nil
        } catch {
            let failure = error as? ClaudeOAuthFailure
            let providerError = failure?.error ?? (error as? ProviderError)
            if case .rateLimited = providerError {
                persisted.rateLimitCount = min(persisted.rateLimitCount + 1, 3)
                let delay = [900.0, 1800.0, 3600.0][persisted.rateLimitCount - 1]
                persisted.nextAttempt = max(now().addingTimeInterval(delay), failure?.nextRetryDate ?? .distantPast)
                persisted.failure = "HTTP 429"
            } else {
                persisted.failure = providerError?.localizedDescription ?? "usage unavailable"
            }
        }
        inFlight = nil
        save()
        let end = now()
        let latestLocal = (try? fetchLocal()).flatMap { valid($0, at: end) }
        if let latestLocal, latestLocal.meterWindow != nil,
           end.timeIntervalSince(latestLocal.fetchedAt) <= Self.localFreshness {
            return newest(latestLocal, persisted.apiSnapshot.flatMap { valid($0, at: end) })!.withNotice(nil)
        }
        if let snapshot = newest(latestLocal, persisted.apiSnapshot.flatMap { valid($0, at: end) }) {
            return snapshot.withNotice(pauseNotice(at: end))
        }
        throw ProviderError.unavailable(pauseNotice(at: end) ?? "No current Claude quota windows. Open Code to publish usage or wait for the API fallback.")
    }

    private func valid(_ snapshot: UsageSnapshot, at date: Date) -> UsageSnapshot? {
        guard Self.supports(snapshot), snapshot.fetchedAt <= date.addingTimeInterval(5) else { return nil }
        let windows = snapshot.windows.filter {
            $0.usedPercent.isFinite && ($0.resetsAt.map { $0 > date } ?? (date.timeIntervalSince(snapshot.fetchedAt) <= 600))
        }
        guard !windows.isEmpty else { return nil }
        return UsageSnapshot(provider: .claude, plan: snapshot.plan, windows: windows, fetchedAt: snapshot.fetchedAt,
                             source: snapshot.source, account: snapshot.account, accountID: snapshot.accountID)
    }
    private func newest(_ local: UsageSnapshot?, _ api: UsageSnapshot?) -> UsageSnapshot? {
        // Prefer the candidate with a valid 5h window; weekly never substitutes its ring.
        let candidates = [local, api].compactMap { $0 }
        let metered = candidates.filter { $0.meterWindow != nil }
        return (metered.isEmpty ? candidates : metered).max { $0.fetchedAt < $1.fetchedAt }
    }
    private func pauseNotice(at date: Date) -> String? {
        if let failure = persisted.failure, let deadline = persisted.nextAttempt, deadline > date {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            return "API fallback paused (\(failure)) until \(formatter.string(from: deadline)); showing last observed usage when available."
        }
        return "Last observed Claude usage; Code updates automatically, API fallback checks at most every 5 minutes."
    }
    private func save() {
        if let data = try? JSONEncoder().encode(persisted) { defaults.set(data, forKey: Self.persistenceKey) }
    }
}

private extension UsageSnapshot {
    func withNotice(_ notice: String?) -> UsageSnapshot {
        UsageSnapshot(provider: provider, plan: plan, windows: windows, fetchedAt: fetchedAt,
                      source: source, account: account, accountID: accountID, notice: notice)
    }
}
