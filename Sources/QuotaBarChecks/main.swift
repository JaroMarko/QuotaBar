import QuotaBarCore
import Foundation

struct CheckRunner {
    private(set) var passed = 0
    private(set) var failed = 0

    mutating func check(_ condition: @autoclosure () -> Bool, _ name: String) {
        if condition() {
            passed += 1
            print("PASS  \(name)")
        } else {
            failed += 1
            print("FAIL  \(name)")
        }
    }

    mutating func checkThrows(_ name: String, _ body: () throws -> Void) {
        do {
            try body()
            failed += 1
            print("FAIL  \(name)")
        } catch {
            passed += 1
            print("PASS  \(name)")
        }
    }
}

func snapshot(used: Double, reset: TimeInterval) -> UsageSnapshot {
    UsageSnapshot(
        provider: .codex,
        plan: "Pro",
        windows: [UsageWindow(
            id: "weekly",
            name: "Weekly",
            usedPercent: used,
            resetsAt: Date(timeIntervalSince1970: reset),
            durationMinutes: 10_080
        )],
        fetchedAt: Date(timeIntervalSince1970: 1)
    )
}

var runner = CheckRunner()

let high = UsageWindow(id: "high", name: "High", usedPercent: 125, resetsAt: nil, durationMinutes: nil)
let low = UsageWindow(id: "low", name: "Low", usedPercent: -5, resetsAt: nil, durationMinutes: nil)
runner.check(high.clampedUsedPercent == 100, "usage clamps above 100")
runner.check(high.remainingPercent == 0, "remaining clamps at zero")
runner.check(low.clampedUsedPercent == 0, "usage clamps below zero")
runner.check(UsageFormatting.percent(42.4) == "42%", "percentage formatting")

let highest = UsageSnapshot(
    provider: .codex,
    plan: "Pro",
    windows: [
        UsageWindow(id: "session", name: "Session", usedPercent: 20, resetsAt: nil, durationMinutes: 300),
        UsageWindow(id: "weekly", name: "Weekly", usedPercent: 72, resetsAt: nil, durationMinutes: 10_080)
    ],
    fetchedAt: Date()
)
runner.check(highest.highestUsedPercent == 72, "highest active usage selection")

let codexResult: [String: Any] = [
    "rateLimits": [
        "limitId": "codex",
        "planType": "pro",
        "primary": ["usedPercent": 34, "windowDurationMins": 300, "resetsAt": 2_000_000_000],
        "secondary": ["usedPercent": 51, "windowDurationMins": 10_080, "resetsAt": 2_000_100_000]
    ],
    "rateLimitsByLimitId": [
        "codex": ["limitId": "codex"],
        "special": [
            "limitId": "special",
            "limitName": "Special model",
            "primary": ["usedPercent": 12, "windowDurationMins": 300]
        ]
    ]
]
do {
    let decoded = try CodexUsageDecoder.decode(rateLimitResult: codexResult, accountResult: nil, now: Date(timeIntervalSince1970: 1))
    runner.check(decoded.plan == "Pro", "Codex plan decoding")
    runner.check(decoded.windows.count == 3, "Codex main and model windows")
    runner.check(decoded.windows.map(\.name) == ["5-hour session", "Weekly", "Special model · 5-hour session"], "Codex window naming")
} catch {
    runner.check(false, "Codex valid response decoding")
}
runner.checkThrows("Codex malformed response rejection") {
    _ = try CodexUsageDecoder.decode(rateLimitResult: [:], accountResult: nil, now: Date())
}

let rpcLine2 = #"{"id":2,"result":{"account":{"type":"chatgpt","email":"redacted@example.test","planType":"plus"},"requiresOpenaiAuth":true}}"#
let rpcLine3 = #"{"id":3,"result":{"rateLimits":{"planType":"plus","primary":{"usedPercent":7,"windowDurationMins":300}}}}"#
do {
    let rpcSnapshot = try CodexUsageDecoder.decodeRPCStream(Data("\(rpcLine2)\n\(rpcLine3)\n".utf8), now: Date())
    runner.check(rpcSnapshot.plan == "Plus" && rpcSnapshot.windows.first?.usedPercent == 7, "Codex JSON-RPC stream decoding")
} catch {
    runner.check(false, "Codex JSON-RPC stream decoding")
}

let claudeJSON = #"""
{
  "subscription_type": "max_5x",
  "five_hour": {"utilization": 24.5, "resets_at": "2030-01-01T10:00:00Z"},
  "seven_day": {"utilization": 62, "resets_at": "2030-01-07T10:00:00Z"},
  "seven_day_sonnet": {"utilization": 18, "resets_at": "2030-01-07T10:00:00Z"}
}
"""#.data(using: .utf8)!
do {
    let decoded = try ClaudeUsageDecoder.decode(claudeJSON, planHint: nil, now: Date())
    runner.check(decoded.plan == "Max 5x", "Claude plan decoding")
    runner.check(decoded.windows.map(\.name) == ["5-hour session", "Weekly", "Sonnet weekly"], "Claude quota window decoding")
    runner.check(decoded.windows.first?.resetsAt != nil, "Claude reset date decoding")
} catch {
    runner.check(false, "Claude valid response decoding")
}

let credentialJSON = #"{"claudeAiOauth":{"accessToken":"test-token","subscriptionType":"pro"}}"#.data(using: .utf8)!
do {
    let credential = try ClaudeCredentialLoader.decodeCredential(credentialJSON)
    runner.check(credential.accessToken == "test-token" && credential.planHint == "Pro", "Claude credential schema decoding")
} catch {
    runner.check(false, "Claude credential schema decoding")
}
runner.checkThrows("Claude malformed response rejection") {
    _ = try ClaudeUsageDecoder.decode(Data("{}".utf8), planHint: nil, now: Date())
}

let thresholdEvents = AlertEngine.events(
    previous: snapshot(used: 70, reset: 100),
    current: snapshot(used: 92, reset: 100),
    enabledThresholds: [75, 90, 100],
    resetEnabled: true
)
runner.check(thresholdEvents.compactMap(\.threshold) == [75, 90], "notification threshold crossings")

let resetEvents = AlertEngine.events(
    previous: snapshot(used: 90, reset: 100),
    current: snapshot(used: 2, reset: 200),
    enabledThresholds: [],
    resetEnabled: true
)
runner.check(resetEvents == [UsageAlert(kind: .reset, provider: .codex, windowName: "Weekly", threshold: nil)], "confirmed reset notification")
runner.check(
    AlertEngine.events(previous: nil, current: snapshot(used: 100, reset: 100), enabledThresholds: [75, 90, 100], resetEnabled: true).isEmpty,
    "first refresh notification suppression"
)

// Regression: a noisy child must not block on a full stdout/stderr pipe.
do {
    let result = try ProcessRunner.run(executable: URL(fileURLWithPath: "/bin/sh"),
        arguments: ["-c", "dd if=/dev/zero bs=65536 count=4 2>/dev/null; dd if=/dev/zero bs=65536 count=4 1>&2 2>/dev/null"], timeout: 3)
    runner.check(result.stdout.count == 262_144 && result.stderr.count == 262_144, "drain full stdout and stderr pipes")
} catch { runner.check(false, "drain full stdout and stderr pipes") }
let timeoutStart = Date()
runner.checkThrows("kill child ignoring SIGTERM") {
    _ = try ProcessRunner.run(executable: URL(fileURLWithPath: "/bin/sh"),
        arguments: ["-c", "trap '' TERM; while :; do :; done"], timeout: 0.15)
}
runner.check(Date().timeIntervalSince(timeoutStart) < 3, "subprocess timeout remains bounded")
let measuredAt = Date(timeIntervalSince1970: 2_000_000_000)
let measured = UsageSnapshot(provider: .codex, plan: nil, windows: [
    UsageWindow(id: "session", name: "Session", usedPercent: 31, resetsAt: measuredAt.addingTimeInterval(300), durationMinutes: 300)
], fetchedAt: measuredAt, source: "fixture", account: "fixture")
let fresh = ProviderDisplayState(provider: .codex, snapshot: measured, errorMessage: nil, isRefreshing: false, isStale: false)
runner.check(fresh.meterValue(at: measuredAt) == 31, "fresh meter uses reported quota")
runner.check(fresh.meterValue(at: measuredAt.addingTimeInterval(301)) == nil, "elapsed reset does not invent fresh quota")
let stale = ProviderDisplayState(provider: .codex, snapshot: measured, errorMessage: "Offline", isRefreshing: false, isStale: true)
runner.check(stale.meterValue(at: measuredAt) == nil && stale.snapshot?.fetchedAt == measuredAt, "stale data keeps original timestamp")
let unknown = ProviderDisplayState(provider: .claude, snapshot: nil, errorMessage: nil, isRefreshing: false, isStale: false)
runner.check(unknown.meterValue(at: measuredAt) == nil, "unknown quota is not zero")
runner.checkThrows("reject nonfinite Claude utilization") {
    _ = try ClaudeUsageDecoder.decode(Data(#"{"five_hour":{"utilization":"nan"}}"#.utf8), planHint: nil, now: measuredAt)
}
if let encoded = try? JSONEncoder().encode(measured), let decoded = try? JSONDecoder().decode(UsageSnapshot.self, from: encoded) {
    runner.check(decoded.source == "fixture" && decoded.account == "fixture", "snapshot source/account round trip")
} else { runner.check(false, "snapshot source/account round trip") }

let quiet = UsageSnapshot(provider: .codex, plan: nil, windows: [
    UsageWindow(id: "weekly", name: "Weekly", usedPercent: 30, resetsAt: measuredAt.addingTimeInterval(10_000), durationMinutes: 10_080)
], fetchedAt: measuredAt)
runner.check(RefreshPolicy.interval(previous: quiet, current: quiet, now: measuredAt) == 300, "quiet quota uses slower refresh")
runner.check(RefreshPolicy.interval(previous: nil, current: measured, now: measuredAt) == 60, "new or near-reset quota uses faster refresh")
runner.check(RefreshPolicy.retryInterval(failures: 20, error: .timedOut("test")) == 900, "retry delay is capped")
runner.check(RefreshPolicy.retryInterval(failures: 1, error: .rateLimited("test")) == 600, "rate limit has cooldown")
var ledger = AlertLedger()
let firstAlerts = ledger.take(previous: snapshot(used: 70, reset: 100), current: snapshot(used: 92, reset: 100), thresholds: [75,90], resetEnabled: true)
let repeated = ledger.take(previous: snapshot(used: 70, reset: 100), current: snapshot(used: 92, reset: 100), thresholds: [75,90], resetEnabled: true)
runner.check(firstAlerts.count == 2 && repeated.isEmpty, "deduplicate fluctuating threshold crossings")
if let encoded = try? JSONEncoder().encode(ledger), var restored = try? JSONDecoder().decode(AlertLedger.self, from: encoded) {
    runner.check(restored.take(previous: snapshot(used: 70, reset: 100), current: snapshot(used: 92, reset: 100), thresholds: [75,90], resetEnabled: true).isEmpty, "notification ledger survives restart")
}
let otherAccount = UsageSnapshot(provider: .codex, plan: nil, windows: snapshot(used: 99, reset: 100).windows, fetchedAt: measuredAt, account: "other")
runner.check(AlertEngine.events(previous: snapshot(used: 70, reset: 100), current: otherAccount, enabledThresholds: [90], resetEnabled: true).isEmpty, "account switch does not fabricate crossing")
runner.check(AlertEngine.events(previous: snapshot(used: 90, reset: 100), current: snapshot(used: 90, reset: 200), enabledThresholds: [], resetEnabled: true).isEmpty, "reset timestamp alone is not a confirmed reset")

var history = UsageHistory()
func historicalSnapshot(_ offset: TimeInterval, _ percent: Double, scope: String = "A", resetOffset: TimeInterval = 3600) -> UsageSnapshot {
    UsageSnapshot(provider: .codex, plan: nil, windows: [
        UsageWindow(id: "session", name: "Session", usedPercent: percent, resetsAt: measuredAt.addingTimeInterval(resetOffset), durationMinutes: 60)
    ], fetchedAt: measuredAt.addingTimeInterval(offset), accountID: scope)
}
for i in 0...4 { history.append(historicalSnapshot(Double(i) * 300, Double(i) * 10), maximumSamples: 3) }
runner.check(history.samples.count == 3, "history sample count is bounded")
let latest = historicalSnapshot(1200, 40)
let series = history.series(for: latest, window: latest.windows[0])
runner.check(UsageForecast.estimate(samples: series, now: measuredAt.addingTimeInterval(1200)) != nil, "forecast needs recent multi-point history")
runner.check(UsageForecast.estimate(samples: Array(series.prefix(2)), now: measuredAt.addingTimeInterval(1200)) == nil, "two samples do not produce forecast")
runner.check(UsageForecast.estimate(samples: series, now: measuredAt.addingTimeInterval(1901)) == nil, "stale history suppresses forecast")
let accountB = historicalSnapshot(1200, 40, scope: "B")
runner.check(history.series(for: accountB, window: accountB.windows[0]).isEmpty, "history isolates accounts")
let newCycle = historicalSnapshot(1200, 2, resetOffset: 7200)
runner.check(history.series(for: newCycle, window: newCycle.windows[0]).isEmpty, "history isolates reset cycles")
var decreasing = UsageHistory()
for (offset, value) in [(0.0,10.0),(300.0,50.0),(600.0,20.0)] { decreasing.append(historicalSnapshot(offset,value)) }
runner.check(UsageForecast.estimate(samples: decreasing.samples, now: measuredAt.addingTimeInterval(600)) == nil, "decreasing usage suppresses extrapolation")
history.prune(now: measuredAt.addingTimeInterval(31 * 86_400))
runner.check(history.samples.isEmpty, "history retention removes old samples")
runner.check(UsageForecast.evenUsePercent(window: latest.windows[0], at: measuredAt.addingTimeInterval(1800)) == 50, "even-use guide uses window duration")

print("\nQuotaBar checks: \(runner.passed) passed, \(runner.failed) failed")
if runner.failed > 0 { exit(1) }

if CommandLine.arguments.contains("--live-codex") {
    final class LockedResult: @unchecked Sendable {
        private let lock = NSLock()
        private var stored = false

        func set(_ value: Bool) {
            lock.lock()
            stored = value
            lock.unlock()
        }

        func get() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            return stored
        }
    }

    let completion = DispatchSemaphore(value: 0)
    let result = LockedResult()
    Task.detached {
        do {
            let live = try await CodexUsageProvider().fetch()
            print("PASS  live Codex RPC returned \(live.windows.count) quota window(s)")
            result.set(!live.windows.isEmpty)
        } catch {
            print("FAIL  live Codex RPC: \(error.localizedDescription)")
        }
        completion.signal()
    }
    if completion.wait(timeout: .now() + 35) == .timedOut {
        print("FAIL  live Codex RPC timed out")
        exit(1)
    }
    if !result.get() { exit(1) }
}

if CommandLine.arguments.contains("--live-claude") {
    final class ClaudeLockedResult: @unchecked Sendable {
        private let lock = NSLock()
        private var stored = false

        func set(_ value: Bool) {
            lock.lock()
            stored = value
            lock.unlock()
        }

        func get() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            return stored
        }
    }

    let completion = DispatchSemaphore(value: 0)
    let result = ClaudeLockedResult()
    Task.detached {
        do {
            let live = try await ClaudeUsageProvider().fetch()
            print("PASS  live Claude request returned \(live.windows.count) quota window(s)")
            result.set(!live.windows.isEmpty)
        } catch {
            print("FAIL  live Claude request: \(error.localizedDescription)")
        }
        completion.signal()
    }
    if completion.wait(timeout: .now() + 35) == .timedOut {
        print("FAIL  live Claude request timed out")
        exit(1)
    }
    if !result.get() { exit(1) }
}
