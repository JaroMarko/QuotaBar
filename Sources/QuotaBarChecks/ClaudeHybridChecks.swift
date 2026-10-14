import Foundation
import QuotaBarCore

private final class HybridClock: @unchecked Sendable {
    private let lock = NSLock()
    private var date: Date
    init(_ date: Date) { self.date = date }
    func read() -> Date { lock.lock(); defer { lock.unlock() }; return date }
    func advance(_ seconds: TimeInterval) { lock.lock(); defer { lock.unlock() }; date.addTimeInterval(seconds) }
}
private final class LocalMeasurement: @unchecked Sendable {
    private let lock = NSLock()
    private var snapshot: UsageSnapshot?
    init(_ snapshot: UsageSnapshot?) { self.snapshot = snapshot }
    func read() throws -> UsageSnapshot { lock.lock(); defer { lock.unlock() }; guard let snapshot else { throw ProviderError.localBridgeUnavailable("Fixture") }; return snapshot }
    func set(_ value: UsageSnapshot?) { lock.lock(); defer { lock.unlock() }; snapshot = value }
}
private actor OAuthFixture {
    private var calls = 0
    var failure: ClaudeOAuthFailure?
    let clock: HybridClock
    init(_ clock: HybridClock, failure: ClaudeOAuthFailure? = nil) { self.clock = clock; self.failure = failure }
    func fetch() async throws -> UsageSnapshot {
        calls += 1
        try await Task.sleep(nanoseconds: 10_000_000)
        if let failure { throw failure }
        return hybridSnapshot(at: clock.read(), source: ClaudeOAuthUsageProvider.sourceName, used: 44)
    }
    func count() -> Int { calls }
}
private func hybridSnapshot(at date: Date, source: String = ClaudeSessionUsageProvider.sourceName, used: Double = 24) -> UsageSnapshot {
    UsageSnapshot(provider: .claude, plan: nil, windows: [UsageWindow(id: "claude-five_hour", name: "5h", usedPercent: used,
        resetsAt: date.addingTimeInterval(7200), durationMinutes: 300)], fetchedAt: date, source: source)
}

func verifyClaudeHybrid() async -> Bool {
    var runner = CheckRunner()
    let start = Date(timeIntervalSince1970: 2_000_000_000)
    let clock = HybridClock(start)
    let local = LocalMeasurement(hybridSnapshot(at: start))
    let api = OAuthFixture(clock)
    let name = "QuotaBarHybridChecks.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defer { defaults.removePersistentDomain(forName: name) }
    let hybrid = ClaudeHybridUsageProvider(defaults: defaults, fetchLocal: { try local.read() }, fetchOAuth: { try await api.fetch() }, now: { clock.read() })
    do {
        let fresh = try await hybrid.fetch()
        let initialCalls = await api.count()
        runner.check(fresh.source == ClaudeSessionUsageProvider.sourceName && initialCalls == 0, "hybrid fresh local avoids API and credential reads")
        clock.advance(301)
        let fallback = try await hybrid.fetch()
        let fallbackCalls = await api.count()
        runner.check(fallback.source == ClaudeOAuthUsageProvider.sourceName && fallback.meterWindow?.usedPercent == 44 && fallbackCalls == 1,
                     "hybrid stale local uses server percentages")
        let same = try await hybrid.fetch()
        let repeatedCalls = await api.count()
        runner.check(same.fetchedAt == fallback.fetchedAt && repeatedCalls == 1, "repeated local polls do not repeat API or restamp")
        clock.advance(1); local.set(hybridSnapshot(at: clock.read(), used: 45))
        let resumed = try await hybrid.fetch()
        runner.check(resumed.source == ClaudeSessionUsageProvider.sourceName && resumed.meterWindow?.usedPercent == 45, "new local resumes without waiting for API spacing")
    } catch { runner.check(false, "hybrid source selection: \(error.localizedDescription)") }

    let limitedName = "QuotaBarHybrid429.\(UUID().uuidString)"
    let limitedDefaults = UserDefaults(suiteName: limitedName)!
    defer { limitedDefaults.removePersistentDomain(forName: limitedName) }
    let limitedClock = HybridClock(start)
    let stale = LocalMeasurement(hybridSnapshot(at: start.addingTimeInterval(-400)))
    let failure = ClaudeOAuthFailure(error: .rateLimited("Claude"))
    let limitedAPI = OAuthFixture(limitedClock, failure: failure)
    func limitedProvider() -> ClaudeHybridUsageProvider {
        ClaudeHybridUsageProvider(defaults: limitedDefaults, fetchLocal: { try stale.read() }, fetchOAuth: { try await limitedAPI.fetch() }, now: { limitedClock.read() })
    }
    do {
        let limited = limitedProvider()
        let first = try await limited.fetch()
        runner.check(first.notice?.contains("HTTP 429") == true && first.fetchedAt == start.addingTimeInterval(-400), "429 preserves last known values and reports pause")
        limitedClock.advance(899)
        _ = try await limitedProvider().fetch()
        let beforeRetry = await limitedAPI.count()
        runner.check(beforeRetry == 1, "429 deadline survives restart and repeated polling")
        limitedClock.advance(1); _ = try await limitedProvider().fetch()
        let secondCalls = await limitedAPI.count()
        runner.check(secondCalls == 2, "429 retries only after first15min")
        limitedClock.advance(1799); _ = try await limitedProvider().fetch()
        let waitingCalls = await limitedAPI.count()
        runner.check(waitingCalls == 2, "second429 doubles persisted pause to30min")
        stale.set(hybridSnapshot(at: limitedClock.read(), used: 27))
        let newest = try await limitedProvider().fetch()
        runner.check(newest.notice == nil && newest.meterWindow?.usedPercent == 27, "local data remains available during API429 pause")
    } catch { runner.check(false, "hybrid429 fixture: \(error.localizedDescription)") }
    do {
        limitedClock.advance(1)
        stale.set(hybridSnapshot(at: start.addingTimeInterval(-400)))
        _ = try await limitedProvider().fetch()
        let thirdCalls = await limitedAPI.count()
        runner.check(thirdCalls == 3, "third429 begins60min backoff")
        limitedClock.advance(3599); _ = try await limitedProvider().fetch()
        let pausedCalls = await limitedAPI.count()
        runner.check(pausedCalls == 3, "third429 persisted pause remains60min")
    } catch { runner.check(false, "third429 fixture") }

    let retryName = "QuotaBarRetryAfter.\(UUID().uuidString)"
    let retryDefaults = UserDefaults(suiteName: retryName)!
    defer { retryDefaults.removePersistentDomain(forName: retryName) }
    let retryClock = HybridClock(start)
    let retryLocal = LocalMeasurement(hybridSnapshot(at: start.addingTimeInterval(-400)))
    let retryAPI = OAuthFixture(retryClock, failure: ClaudeOAuthFailure(error: .rateLimited("Claude"), nextRetryDate: start.addingTimeInterval(2400)))
    let retryProvider = ClaudeHybridUsageProvider(defaults: retryDefaults, fetchLocal: { try retryLocal.read() }, fetchOAuth: { try await retryAPI.fetch() }, now: { retryClock.read() })
    do {
        _ = try await retryProvider.fetch(); retryClock.advance(2399); _ = try await retryProvider.fetch()
        let retryCount = await retryAPI.count()
        runner.check(retryCount == 1, "serverRetryAfter longer than15min is respected")
    } catch { runner.check(false, "RetryAfter fixture") }

    let parallelName = "QuotaBarParallel.\(UUID().uuidString)"
    let parallelDefaults = UserDefaults(suiteName: parallelName)!
    defer { parallelDefaults.removePersistentDomain(forName: parallelName) }
    let parallelClock = HybridClock(start)
    let parallelLocal = LocalMeasurement(hybridSnapshot(at: start.addingTimeInterval(-400)))
    let parallelAPI = OAuthFixture(parallelClock)
    let parallel = ClaudeHybridUsageProvider(defaults: parallelDefaults, fetchLocal: { try parallelLocal.read() }, fetchOAuth: { try await parallelAPI.fetch() }, now: { parallelClock.read() })
    do {
        async let first = parallel.fetch(); async let second = parallel.fetch()
        let both = try await (first, second)
        let calls = await parallelAPI.count()
        runner.check(calls == 1 && both.0.fetchedAt == both.1.fetchedAt, "concurrentfallback reads shareoneHTTPrequest")
    } catch { runner.check(false, "concurrentfallback fixture") }
    runner.check(ClaudeOAuthUsageProvider.retryAfter("1200", now: start) == start.addingTimeInterval(1200), "RetryAfter numeric seconds")
    runner.check(ClaudeOAuthUsageProvider.retryAfter("bad", now: start) == nil, "invalid RetryAfter ignored")
    print("Claude hybrid checks: \(runner.passed) passed, \(runner.failed) failed")
    return runner.failed == 0
}
