import AppKit
import Foundation
import QuotaBarCore
import SwiftUI
import UserNotifications

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

private actor ActivityFixtureProvider: UsageProvider {
    nonisolated let kind: ProviderKind
    private var calls = 0
    private var error: ProviderError?
    private var blockNext = false
    private var waiter: CheckedContinuation<Void, Never>?
    init(_ kind: ProviderKind) { self.kind = kind }
    func fetch() async throws -> UsageSnapshot {
        calls += 1
        if blockNext {
            blockNext = false
            await withCheckedContinuation { waiter = $0 }
        }
        if let error { throw error }
        return UsageSnapshot(provider: kind, plan: "Fixture", windows: [
            UsageWindow(id: kind == .claude ? "claude-five_hour" : "weekly", name: "Fixture", usedPercent: 30,
                resetsAt: Date().addingTimeInterval(3600), durationMinutes: 300)
        ], fetchedAt: Date())
    }
    func callCount() -> Int { calls }
    func fail(_ error: ProviderError) { self.error = error }
    func suspendNext() { blockNext = true }
    func resume() { waiter?.resume(); waiter = nil }
}

private actor LocalUsageFixtureProvider: UsageProvider {
    nonisolated let kind = ProviderKind.claude
    nonisolated let requiresNetwork = false
    private var snapshot: UsageSnapshot
    private var calls = 0
    private var unavailable = false
    init(capturedAt: Date) {
        snapshot = Self.measurement(at: capturedAt)
    }
    private static func measurement(at capturedAt: Date) -> UsageSnapshot {
        UsageSnapshot(provider: .claude, plan: nil, windows: [
            UsageWindow(id: "claude-five_hour", name: "5h", usedPercent: 42,
                resetsAt: capturedAt.addingTimeInterval(18000), durationMinutes: 300)
        ], fetchedAt: capturedAt, source: ClaudeSessionUsageProvider.sourceName)
    }
    func fetch() async throws -> UsageSnapshot {
        calls += 1
        if unavailable { throw ProviderError.localBridgeUnavailable("Fixture has no recent local capture.") }
        return snapshot
    }
    func capture(at date: Date) { snapshot = Self.measurement(at: date) }
    func replace(_ value: UsageSnapshot) { snapshot = value; unavailable = false }
    func fail() { unavailable = true }
    func callCount() -> Int { calls }
}

private struct PreviewProvider: UsageProvider {
    let snapshot: UsageSnapshot
    var error: ProviderError? = nil
    var kind: ProviderKind { snapshot.provider }
    func fetch() async throws -> UsageSnapshot {
        if let error { throw error }; return snapshot
    }
}

@MainActor
enum SmokeChecks {
    static func verifyMenu() -> Bool {
        for bounds in [NSRect(x: 0, y: 0, width: 64, height: 24), NSRect(x: 10, y: 5, width: 64, height: 30)] {
            let anchor = StatusInteraction.anchor(in: bounds)
            guard anchor.midX == bounds.midX, anchor.minY == bounds.minY,
                  anchor.height == bounds.height else { return false }
        }
        func event(_ type: NSEvent.EventType, flags: NSEvent.ModifierFlags = []) -> NSEvent? {
            NSEvent.mouseEvent(with: type, location: .zero, modifierFlags: flags, timestamp: 0,
                               windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 0)
        }
        guard !StatusInteraction.isContextClick(event(.leftMouseUp)),
              StatusInteraction.isContextClick(event(.rightMouseUp)),
              StatusInteraction.isContextClick(event(.leftMouseUp, flags: .control)),
              !StatusInteraction.isContextClick(nil) else { return false }
        let preview = NotificationService.testRequest()
        guard preview.content.title == "QuotaBar test notification",
              preview.content.body.contains("have not changed"), preview.trigger == nil,
              preview.content.sound != nil,
              preview.identifier != NotificationService.testRequest().identifier else { return false }
        let menu = StatusInteraction.contextMenu()
        guard menu.items.count == 1, let quit = menu.items.first,
              quit.action == #selector(NSApplication.terminate(_:)),
              quit.target === NSApplication.shared else { return false }
        let name = "QuotaBarMenuChecks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = AppPreferences(defaults: defaults)
        guard preferences.menuBarMode == .concentric else { return false }
        for mode in MenuBarMode.allCases {
            preferences.menuBarMode = mode
            guard AppPreferences(defaults: defaults).menuBarMode == mode,
                  MenuBarIcon.image(states: [], mode: mode).size == NSSize(width: 24, height: 24),
                  MenuBarIcon.image(states: [], mode: mode).isTemplate == (mode != .concentric && mode != .semicircles) else { return false }
        }
        defaults.set("invalid-future-mode", forKey: "menuBarMode")
        guard AppPreferences(defaults: defaults).menuBarMode == .concentric,
              MenuBarMode.iconOnly.providers.isEmpty,
              MenuBarMode.claude.providers == [.claude], MenuBarMode.codex.providers == [.codex] else { return false }
        defaults.removeObject(forKey: "menuBarMode")
        let now = Date()
        func states(_ claude: Double, _ codex: Double) -> [ProviderDisplayState] {
            zip([ProviderKind.claude, .codex], [claude, codex]).map { provider, value in
                ProviderDisplayState(provider: provider, snapshot: UsageSnapshot(provider: provider, plan: nil,
                    windows: [UsageWindow(id: provider == .claude ? "claude-five_hour" : "weekly", name: "Fixture", usedPercent: value,
                        resetsAt: now.addingTimeInterval(3600), durationMinutes: 300)], fetchedAt: now),
                    errorMessage: nil, isRefreshing: false, isStale: false)
            }
        }
        func pixels(_ mode: MenuBarMode, _ states: [ProviderDisplayState], appearance: NSAppearance.Name = .aqua) -> Data? {
            guard let tiff = MenuBarIcon.image(states: states, mode: mode, now: now, appearance: NSAppearance(named: appearance)).tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
            return bitmap.representation(using: .png, properties: [:])
        }
        let first = states(20, 30), second = states(20, 80)
        guard let claudePixels = pixels(.claude, first),
              claudePixels == pixels(.claude, second),
              pixels(.codex, first) != pixels(.codex, second),
              pixels(.concentric, first) != pixels(.concentric, second),
              pixels(.semicircles, first) != pixels(.semicircles, second),
              pixels(.iconOnly, first) == pixels(.iconOnly, second),
              pixels(.claude, first) != pixels(.claude, []),
              pixels(.codex, first) != pixels(.codex, []) else { return false }

        // Colour images must adapt their central glyph/track, while inactive modes remain system templates.
        for mode in [MenuBarMode.concentric, .semicircles] {
            guard pixels(mode, first, appearance: .aqua) != pixels(mode, first, appearance: .darkAqua) else { return false }
            var inactive = first
            for index in inactive.indices { inactive[index].isInactive = true }
            guard MenuBarIcon.image(states: inactive, mode: mode).isTemplate else { return false }
        }

        let store = UsageStore(providers: [], defaults: defaults, activityProbe: { _ in true })
        let controller = NSHostingController(rootView: QuotaBarMenuView(store: store, refreshOnAppear: false))
        controller.sizingOptions = [.preferredContentSize]
        controller.view.layoutSubtreeIfNeeded()
        let size = controller.view.fittingSize
        guard size.width == 410, size.height > 150, size.height < 350 else { return false }
        print("PASS menu: hosted size \(size), centred anchor, left/right/control click routing, Quit target, test notification payload, five persisted 24pt modes, light/dark combined rings, inactive template fallback")
        return true
    }

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
                               historyPersistence: persistence, activityProbe: { _ in true })
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
        let restarted = UsageStore(providers: [provider], preferences: preferences, defaults: defaults, historyPersistence: persistence, activityProbe: { _ in true })
        await restarted.refreshAll(force: true)
        guard await provider.callCount() == 4, restarted.states[.codex]?.errorHelp != nil,
              restarted.nextRefreshAt[.codex] == store.nextRefreshAt[.codex] else { return false }

        guard let loaded = try? await persistence.load(), loaded.samples.count == 2 else { return false }
        await store.clearHistory()
        guard store.history.samples.isEmpty, (try? await persistence.load())?.samples.isEmpty == true else { return false }
        guard await verifyActivity(), await verifyLocalUsage(), await verifyHybridStore() else { return false }
        print("PASS store: stale retention, retry scheduling, manual recovery, 429 cooldown across restart, error help, history persistence/clear")
        return true
    }

    private static func verifyHybridStore() async -> Bool {
        let name = "QuotaBarHybridStoreChecks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        defer { try? FileManager.default.removeItem(at: directory) }
        let captured = Date().addingTimeInterval(-1200)
        let windows = [UsageWindow(id: "claude-five_hour", name: "5h", usedPercent: 42,
            resetsAt: Date().addingTimeInterval(3600), durationMinutes: 300)]
        let cached = UsageSnapshot(provider: .claude, plan: nil, windows: windows,
            fetchedAt: captured, source: "Claude OAuth fallback", accountID: "opaque-fixture")
        defaults.set(try? JSONEncoder().encode(cached), forKey: "cachedSnapshot.claude")
        // The former global cooldown must not stop local bridge reads.
        defaults.set(Date().addingTimeInterval(600), forKey: "rateLimitedUntil.claude")
        let provider = LocalUsageFixtureProvider(capturedAt: captured)
        await provider.replace(cached)
        let store = UsageStore(providers: [provider], defaults: defaults,
            historyPersistence: HistoryPersistence(url: directory.appendingPathComponent("history.json")),
            networkAvailable: false, activityProbe: { _ in true })
        guard store.states[.claude]?.snapshot == cached,
              store.states[.claude]?.meterValue() == 42,
              defaults.object(forKey: "rateLimitedUntil.claude") == nil else { return false }
        let paused = UsageSnapshot(provider: .claude, plan: nil, windows: windows,
            fetchedAt: captured, source: "Claude OAuth fallback", accountID: "opaque-fixture",
            notice: "OAuth quota checks paused; last observed usage retained.")
        await provider.replace(paused)
        await store.refreshAll(force: true)
        guard store.states[.claude]?.snapshot?.notice == paused.notice,
              store.states[.claude]?.snapshot?.fetchedAt == captured,
              store.states[.claude]?.errorMessage == nil,
              store.states[.claude]?.meterValue() == 42,
              store.history.samples.isEmpty else { return false }
        // Source-only changes are not additional quota observations.
        let local = UsageSnapshot(provider: .claude, plan: nil, windows: windows,
            fetchedAt: captured, source: ClaudeSessionUsageProvider.sourceName)
        await provider.replace(local)
        await store.refreshAll(force: true)
        guard store.history.samples.isEmpty, store.states[.claude]?.snapshot == local else { return false }
        await provider.capture(at: Date())
        await store.refreshAll(force: true)
        guard await provider.callCount() == 3,
              store.history.samples.count == 1,
              store.states[.claude]?.errorMessage == nil else { return false }
        let partial = UsageSnapshot(provider: .claude, plan: nil, windows: [
            UsageWindow(id: "claude-seven_day", name: "7d", usedPercent: 12,
                resetsAt: Date().addingTimeInterval(86400), durationMinutes: 10080)
        ], fetchedAt: Date().addingTimeInterval(10), source: "Claude OAuth fallback")
        defaults.set(try? JSONEncoder().encode(partial), forKey: "cachedSnapshot.claude")
        let partialStore = UsageStore(providers: [provider], defaults: defaults,
            historyPersistence: HistoryPersistence(url: directory.appendingPathComponent("partial-history.json")),
            networkAvailable: false, activityProbe: { _ in true })
        await provider.replace(local)
        await partialStore.refreshAll(force: true)
        guard partialStore.states[.claude]?.snapshot == local,
              partialStore.states[.claude]?.meterValue() == 42,
              partialStore.history.samples.isEmpty else { return false }
        // Once a valid 5-hour meter is present, an older meter still cannot overwrite it.
        let olderMeter = UsageSnapshot(provider: .claude, plan: nil, windows: [
            UsageWindow(id: "claude-five_hour", name: "5h", usedPercent: 10,
                resetsAt: Date().addingTimeInterval(3600), durationMinutes: 300)
        ], fetchedAt: captured.addingTimeInterval(-10), source: ClaudeSessionUsageProvider.sourceName)
        await provider.replace(olderMeter)
        await partialStore.refreshAll(force: true)
        guard partialStore.states[.claude]?.snapshot == local,
              partialStore.states[.claude]?.meterValue() == 42,
              partialStore.history.samples.isEmpty else { return false }
        print("PASS hybrid store: OAuth cache, idle ring, notice/source deduplication, local read during 429, older valid 5h recovery from partial API response")
        return true
    }

    private static func verifyLocalUsage() async -> Bool {
        let name = "QuotaBarLocalChecks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        defer { try? FileManager.default.removeItem(at: directory) }
        let capturedAt = Date().addingTimeInterval(-30)
        let old = UsageSnapshot(provider: .claude, plan: nil, windows: [], fetchedAt: Date(), source: "Claude OAuth usage")
        defaults.set(try? JSONEncoder().encode(old), forKey: "cachedSnapshot.claude")
        defaults.set(Date().addingTimeInterval(600), forKey: "rateLimitedUntil.claude")
        let provider = LocalUsageFixtureProvider(capturedAt: capturedAt)
        let codex = ActivityFixtureProvider(.codex)
        let preferences = AppPreferences(defaults: defaults)
        preferences.notification75 = false; preferences.notification90 = false
        preferences.notification100 = false; preferences.notificationReset = false
        let store = UsageStore(providers: [provider, codex], preferences: preferences, defaults: defaults,
            historyPersistence: HistoryPersistence(url: directory.appendingPathComponent("history.json")),
            networkAvailable: false, activityProbe: { _ in true })
        guard store.states[.claude]?.snapshot == nil,
              defaults.object(forKey: "rateLimitedUntil.claude") == nil else { return false }
        await store.refreshAll(force: true)
        guard await provider.callCount() == 1, await codex.callCount() == 0,
              store.states[.claude]?.snapshot?.fetchedAt == capturedAt,
              store.states[.claude]?.errorMessage == nil,
              store.states[.codex]?.errorMessage?.contains("Offline") == true,
              store.history.samples.isEmpty else { return false } // no alerts/history on source migration
        await store.refreshAll(force: true)
        guard store.history.samples.isEmpty, store.states[.claude]?.snapshot?.fetchedAt == capturedAt else { return false }
        let newer = capturedAt.addingTimeInterval(1)
        await provider.capture(at: newer)
        await store.refreshAll(force: true)
        guard store.history.samples.count == 1, store.history.samples.first?.measuredAt == newer,
              store.history.samples.first?.accountScope == "unknown" else { return false }
        await store.refreshAll(force: true)
        guard store.history.samples.count == 1 else { return false }
        await provider.capture(at: capturedAt)
        await store.refreshAll(force: true)
        guard store.states[.claude]?.snapshot?.fetchedAt == newer, store.history.samples.count == 1 else { return false }
        await provider.fail()
        await store.refreshAll(force: true)
        guard store.states[.claude]?.isStale == true,
              store.nextRefreshAt[.claude]?.timeIntervalSinceNow ?? 0 <= 20,
              store.states[.claude]?.snapshot?.fetchedAt == newer else { return false }
        print("PASS local Claude store: offline read, 429 migration, capture age, duplicate suppression, older capture rejection, 20s retry")
        return true
    }

    private static func verifyActivity() async -> Bool {
        let name = "QuotaBarActivityChecks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        defer { try? FileManager.default.removeItem(at: directory) }
        let preferences = AppPreferences(defaults: defaults)
        preferences.notification75 = false; preferences.notification90 = false
        preferences.notification100 = false; preferences.notificationReset = false
        let claude = ActivityFixtureProvider(.claude), codex = ActivityFixtureProvider(.codex)
        var running = Set<ProviderKind>()
        var unverified = false
        let store = UsageStore(providers: [claude, codex], preferences: preferences, defaults: defaults,
            historyPersistence: HistoryPersistence(url: directory.appendingPathComponent("history.json")),
            activityProbe: { unverified ? nil : running.contains($0) })
        guard store.orderedStates.allSatisfy({ $0.isInactive && $0.meterValue() == nil }) else { return false }
        await store.refreshAll(force: true)
        guard await claude.callCount() == 0, await codex.callCount() == 0 else { return false }
        running.insert(.claude)
        await store.refreshAll(force: false)
        guard await claude.callCount() == 1, await codex.callCount() == 0,
              store.states[.claude]?.isInactive == false else { return false }
        running.insert(.codex)
        await store.refreshAll(force: false)
        guard await claude.callCount() == 1, await codex.callCount() == 1 else { return false }
        running.remove(.claude)
        await store.refreshAll(force: true)
        guard await claude.callCount() == 1, await codex.callCount() == 2,
              store.states[.claude]?.isInactive == true, store.states[.claude]?.snapshot != nil,
              store.states[.claude]?.meterValue() == nil else { return false }
        running.remove(.codex)
        await store.refreshAll(force: true)
        guard await codex.callCount() == 2, store.states[.codex]?.isInactive == true else { return false }
        running.insert(.claude)
        await claude.fail(.rateLimited("Claude"))
        await store.refreshAll(force: false)
        guard await claude.callCount() == 2 else { return false }
        let deadline = store.nextRefreshAt[.claude]
        running.remove(.claude); await store.refreshAll(force: true)
        running.insert(.claude); await store.refreshAll(force: true)
        guard await claude.callCount() == 2, store.nextRefreshAt[.claude] == deadline,
              store.states[.claude]?.errorHelp != nil else { return false }
        unverified = true
        await store.refreshAll(force: true)
        guard store.orderedStates.allSatisfy({ !$0.isInactive && $0.meterValue() == nil && $0.errorHelp != nil }),
              await codex.callCount() == 2 else { return false }
        unverified = false
        running = [.codex]
        await codex.suspendNext()
        let pending = Task { await store.refreshAll(force: true) }
        let timeout = Date().addingTimeInterval(2)
        while await codex.callCount() < 3 && Date() < timeout { await Task.yield() }
        guard await codex.callCount() == 3 else { pending.cancel(); return false }
        running.remove(.codex)
        await store.refreshAll(force: false)
        await codex.resume()
        await pending.value
        guard store.states[.codex]?.isInactive == true, store.states[.codex]?.meterValue() == nil,
              store.states[.codex]?.errorMessage == nil else { return false }
        guard ProviderActivityProbe.matchesCLIName("claude", provider: .claude),
              ProviderActivityProbe.matchesCLIName("codex", provider: .codex),
              !ProviderActivityProbe.matchesCLIName("claude-helper", provider: .claude),
              !ProviderActivityProbe.eligibleProcess(uid: 501, parent: 42, ownUID: 501, ownPID: 42),
              !ProviderActivityProbe.eligibleProcess(uid: 502, parent: 10, ownUID: 501, ownPID: 42),
              ProviderActivityProbe.eligibleProcess(uid: 501, parent: 10, ownUID: 501, ownPID: 42) else { return false }
        print("PASS activity: both off skip requests, independent resume, cached values hidden,429 retained,unknown detection,in-flight stop,own child/UID filters")
        print("Native activity probe: Claude \(String(describing: ProviderActivityProbe.isRunning(.claude))), Codex \(String(describing: ProviderActivityProbe.isRunning(.codex)))")
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

    // Offline fixture rendering tests the actual native layout, not a mockup.
    static func writePopupPreview(path: String) async -> Bool {
        let now = Date()
        let name = "QuotaBarPreview.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let snapshots = [ProviderKind.claude, .codex].map { kind in
            UsageSnapshot(provider: kind, plan: "Pro", windows: [
                UsageWindow(id: kind == .claude ? "claude-five_hour" : "codex-primary",
                            name: "5-hour session", usedPercent: 24, resetsAt: now.addingTimeInterval(7200), durationMinutes: 300),
                UsageWindow(id: kind == .claude ? "claude-seven_day" : "codex-secondary",
                            name: "Weekly", usedPercent: 82, resetsAt: now.addingTimeInterval(3 * 86400), durationMinutes: 10080)
            ], fetchedAt: now, source: "Preview", account: "Preview")
        }
        for snapshot in snapshots {
            defaults.set(try? JSONEncoder().encode(snapshot), forKey: "cachedSnapshot.\(snapshot.provider.rawValue)")
        }
        let preferences = AppPreferences(defaults: defaults)
        preferences.notification75 = false; preferences.notification90 = false
        preferences.notification100 = false; preferences.notificationReset = false
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        defer { try? FileManager.default.removeItem(at: directory) }
        func makeStore(_ snapshots: [UsageSnapshot], error: ProviderError? = nil) -> UsageStore {
            UsageStore(providers: snapshots.map { PreviewProvider(snapshot: $0, error: error) }, preferences: preferences,
                defaults: defaults, historyPersistence: HistoryPersistence(url: directory.appendingPathComponent("history.json")), activityProbe: { _ in true })
        }
        let store = makeStore(snapshots)
        let base = URL(fileURLWithPath: path).deletingPathExtension().path
        guard renderPopup(store: store, path: base + "-stale.png", appearance: .aqua) else { return false }
        await store.refreshAll(force: true)
        guard renderPopup(store: store, path: path, appearance: .aqua),
              renderPopup(store: store, path: base + "-dark.png", appearance: .darkAqua) else { return false }
        let idleSnapshots = snapshots.map { snapshot in
            snapshot.provider == .claude ? UsageSnapshot(provider: .claude, plan: snapshot.plan, windows: snapshot.windows,
                fetchedAt: now.addingTimeInterval(-1200), source: ClaudeSessionUsageProvider.sourceName) : snapshot
        }
        let idleStore = makeStore(idleSnapshots)
        await idleStore.refreshAll(force: true)
        guard idleStore.states[.claude]?.hasStaleData() == true,
              idleStore.states[.claude]?.meterValue() == 24,
              renderPopup(store: idleStore, path: base + "-idle.png", appearance: .aqua) else { return false }
        let pausedSnapshots = snapshots.map { snapshot in
            snapshot.provider == .claude ? UsageSnapshot(provider: .claude, plan: snapshot.plan, windows: snapshot.windows,
                fetchedAt: now.addingTimeInterval(-1200), source: ClaudeOAuthUsageProvider.sourceName,
                notice: "API fallback paused (HTTP 429) until 23:15; showing last observed usage when available.") : snapshot
        }
        let pausedStore = makeStore(pausedSnapshots)
        await pausedStore.refreshAll(force: true)
        guard pausedStore.states[.claude]?.meterValue() == 24,
              renderPopup(store: pausedStore, path: base + "-api-pause.png", appearance: .aqua) else { return false }
        let extraSnapshots = snapshots.map { snapshot in
            UsageSnapshot(provider: snapshot.provider, plan: snapshot.plan, windows: snapshot.windows + (0..<8).map { index in
                UsageWindow(id: "model-\(index)", name: "Additional model \(index)", usedPercent: Double(90 + index),
                            resetsAt: now.addingTimeInterval(86400), durationMinutes: 10080)
            }, fetchedAt: now)
        }
        let extraStore = makeStore(extraSnapshots)
        await extraStore.refreshAll(force: true)
        guard renderPopup(store: extraStore, path: base + "-extra.png", appearance: .aqua) else { return false }
        let errorStore = makeStore(snapshots, error: .rateLimited("Fixture provider"))
        await errorStore.refreshAll(force: true)
        guard renderPopup(store: errorStore, path: base + "-error.png", appearance: .aqua) else { return false }
        let inactive = UsageStore(providers: [], preferences: preferences, defaults: defaults, activityProbe: { _ in false })
        guard renderPopup(store: inactive, path: base + "-inactive.png", appearance: .aqua) else { return false }
        for provider in ProviderKind.allCases { defaults.removeObject(forKey: "cachedSnapshot.\(provider.rawValue)") }
        return renderPopup(store: makeStore([]), path: base + "-unknown.png", appearance: .aqua)
    }

    private static func renderPopup(store: UsageStore, path: String, appearance: NSAppearance.Name) -> Bool {
        let view = NSHostingView(rootView: QuotaBarMenuView(store: store, refreshOnAppear: false)
            .background(Color(nsColor: .windowBackgroundColor)))
        view.appearance = NSAppearance(named: appearance)
        let size = view.fittingSize
        guard size.width == 410, size.height > 150, size.height <= 620 else {
            print("FAIL popup fitting size: \(size)"); return false
        }
        view.frame = NSRect(origin: .zero, size: size)
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return false }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { return false }
        do { try png.write(to: URL(fileURLWithPath: path), options: .atomic) }
        catch { print("FAIL popup preview: \(error)"); return false }
        print("PASS no-scroll native popup: \(Int(size.width)) × \(Int(size.height))pt, \(URL(fileURLWithPath: path).lastPathComponent)")
        return true
    }

    static func writeIconPreview(path: String) {
        let now = Date()
        let combinations: [(Double?, Double?)] = [(10,25),(60,85),(100,100),(nil,nil)]
        let modes = MenuBarMode.allCases
        print("Provider artwork loaded: Claude \(MenuBarIcon.hasClaudeArtwork), OpenAI \(MenuBarIcon.hasOpenAIArtwork)")
        for dark in [false, true] {
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
        let labelColour = dark ? NSColor.white : NSColor.black
        let image = NSImage(size: NSSize(width: 720, height: 320), flipped: false) { _ in
            (dark ? NSColor(white: 0.12, alpha: 1) : NSColor.white).setFill()
            NSBezierPath(rect: NSRect(x: 0, y: 0, width: 720, height: 320)).fill()
            let labels = ["Concentric", "Claude", "Codex", "Icon only", "Semicircles"]
            for (index, label) in labels.enumerated() {
                (label as NSString).draw(at: NSPoint(x: 130 + index * 116, y: 290),
                    withAttributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: labelColour])
            }
            for (row, values) in combinations.enumerated() {
                let states = zip([ProviderKind.claude,.codex], [values.0,values.1]).map { kind, used in
                    ProviderDisplayState(provider: kind, snapshot: used.map { value in
                        UsageSnapshot(provider: kind, plan: nil, windows: [UsageWindow(id: kind == .claude ? "claude-five_hour" : "fixture", name: "Fixture", usedPercent: value,
                            resetsAt: now.addingTimeInterval(3600), durationMinutes: 60)], fetchedAt: now)
                    }, errorMessage: nil, isRefreshing: false, isStale: false)
                }
                let y = CGFloat(224 - row * 65)
                let label = values.0 == nil ? "Unavailable" : "\(Int(values.0!)) / \(Int(values.1!))% used"
                (label as NSString).draw(at: NSPoint(x: 8, y: y + 12),
                    withAttributes: [.font: NSFont.systemFont(ofSize: 10), .foregroundColor: labelColour])
                for (column, mode) in modes.enumerated() {
                    let icon = MenuBarIcon.image(states: states, mode: mode, now: now, appearance: appearance)
                    let x = CGFloat(130 + column * 116)
                    // Single-provider/template modes are tinted by macOS; emulate that in the dark preview.
                    if icon.isTemplate && dark {
                        let tinted = NSImage(size: icon.size)
                        tinted.lockFocus()
                        NSColor.white.setFill(); NSBezierPath(rect: NSRect(origin: .zero, size: icon.size)).fill()
                        icon.draw(in: NSRect(origin: .zero, size: icon.size), from: .zero, operation: .destinationIn, fraction: 1)
                        tinted.unlockFocus()
                        tinted.draw(in: NSRect(x: x, y: y + 12, width: 24, height: 24))
                        tinted.draw(in: NSRect(x: x + 32, y: y, width: 48, height: 48))
                    } else {
                        icon.draw(in: NSRect(x: x, y: y + 12, width: 24, height: 24))
                        icon.draw(in: NSRect(x: x + 32, y: y, width: 48, height: 48))
                    }
                }
            }
            return true
        }
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else { return }
        let destination = dark ? URL(fileURLWithPath: path).deletingPathExtension().path + "-dark.png" : path
        try? png.write(to: URL(fileURLWithPath: destination), options: .atomic)
        }
    }
}
