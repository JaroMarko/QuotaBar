import AppKit
import Foundation
import QuotaBarCore

// Explicit developer-only commands; fixtures never use provider credentials.
actor FixtureProvider: UsageProvider {
    nonisolated let kind = ProviderKind.codex
    private var calls = 0
    func fetch() async throws -> UsageSnapshot {
        calls += 1
        if calls == 2 { throw ProviderError.networkUnavailable("Fixture") }
        if calls == 4 { throw ProviderError.rateLimited("Fixture") }
        return UsageSnapshot(provider: .codex, plan: "Fixture", windows: [
            UsageWindow(id: "session", name: "Session", usedPercent: Double(calls * 10),
                        resetsAt: Date().addingTimeInterval(3600), durationMinutes: 60)
        ], fetchedAt: Date(), source: "Fixture", accountID: "fixture-account")
    }
    func callCount() -> Int { calls }
}

@MainActor
enum SmokeChecks {
    static func verifyStore() async -> Bool {
        let name = "QuotaBarChecks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        defer { try? FileManager.default.removeItem(at: directory) }
        let persistence = HistoryPersistence(url: directory.appendingPathComponent("history.json"))
        let preferences = AppPreferences(defaults: defaults)
        preferences.notification75 = false; preferences.notification90 = false
        preferences.notification100 = false; preferences.notificationReset = false
        let provider = FixtureProvider()
        let store = UsageStore(providers: [provider], preferences: preferences, defaults: defaults,
                               historyPersistence: persistence)
        await store.refreshAll(force: true)
        guard let original = store.states[.codex]?.snapshot, !store.isRefreshing else { return false }
        await store.refreshAll(force: true)
        guard store.states[.codex]?.snapshot == original, store.states[.codex]?.isStale == true else { return false }
        await store.refreshAll(force: false)
        guard await provider.callCount() == 2 else { return false }
        await store.refreshAll(force: true)
        guard store.states[.codex]?.isStale == false, store.history.samples.count == 2 else { return false }
        await store.refreshAll(force: true)
        await store.refreshAll(force: true)
        guard await provider.callCount() == 4 else { return false } // even manual refresh respects 429
        guard let loaded = try? await persistence.load(), loaded.samples.count == 2 else { return false }
        await store.clearHistory()
        guard store.history.samples.isEmpty, (try? await persistence.load())?.samples.isEmpty == true else { return false }
        print("PASS store: stale retention, retry scheduling, manual recovery, 429 cooldown, history persistence/clear")
        return true
    }

    static func writeLiveReport(path: String) async {
        let store = UsageStore.shared
        let deadline = Date().addingTimeInterval(45)
        while store.lastRefreshAt == nil && Date() < deadline {
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        let rows: [[String: Any]] = store.orderedStates.map { state in
            ["provider": state.provider.rawValue, "windows": state.snapshot?.windows.count ?? 0,
             "stale": state.hasStaleData(), "source": state.snapshot?.source ?? "unknown",
             "error": state.errorMessage ?? "none"]
        }
        let report: [String: Any] = ["startupRefreshCompleted": store.lastRefreshAt != nil,
                                    "historySamples": store.history.samples.count, "providers": rows]
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: URL(fileURLWithPath: path), options: .atomic)
        }
        NSApplication.shared.terminate(nil)
    }

    static func writeIconPreview(path: String) {
        let now = Date()
        let combinations: [(Double?, Double?)] = [(10,25),(60,85),(100,100),(nil,nil)]
        print("Provider artwork loaded: Claude \(MenuBarIcon.hasClaudeArtwork), OpenAI \(MenuBarIcon.hasOpenAIArtwork)")
        let image = NSImage(size: NSSize(width: 440, height: 100), flipped: false) { _ in
            NSColor.white.setFill(); NSBezierPath(rect: NSRect(x: 0,y: 0,width: 440,height: 100)).fill()
            for (index, values) in combinations.enumerated() {
                let states = zip([ProviderKind.claude,.codex], [values.0,values.1]).map { kind, used in
                    ProviderDisplayState(provider: kind, snapshot: used.map { value in
                        UsageSnapshot(provider: kind, plan: nil, windows: [UsageWindow(id: "fixture", name: "Fixture", usedPercent: value,
                            resetsAt: now.addingTimeInterval(3600), durationMinutes: 60)], fetchedAt: now)
                    }, errorMessage: nil, isRefreshing: false, isStale: false)
                }
                let icon = MenuBarIcon.image(states: states, now: now)
                icon.draw(in: NSRect(x: 24 + CGFloat(index)*110,y: 48,width: MenuBarIcon.size.width,height: MenuBarIcon.size.height))
                let label = values.0 == nil ? "Unavailable" : "\(Int(values.0!)) / \(Int(values.1!))% used"
                (label as NSString).draw(at: NSPoint(x: 14 + CGFloat(index)*110,y: 15),
                    withAttributes: [.font: NSFont.systemFont(ofSize: 10), .foregroundColor: NSColor.black])
            }
            return true
        }
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: path), options: .atomic)
    }
}
