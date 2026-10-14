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
