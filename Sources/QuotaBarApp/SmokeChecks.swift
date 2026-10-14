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
        let store = UsageStore(providers: [], defaults: defaults)
        let controller = NSHostingController(rootView: QuotaBarMenuView(store: store, refreshOnAppear: false))
        controller.sizingOptions = [.preferredContentSize]
        controller.view.layoutSubtreeIfNeeded()
        let size = controller.view.fittingSize
        guard size.width == 410, size.height > 150, size.height < 350 else { return false }
        print("PASS menu: hosted size \(size), centred anchor, left/right/control click routing, Quit target, test notification payload")
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
                defaults: defaults, historyPersistence: HistoryPersistence(url: directory.appendingPathComponent("history.json")))
        }
        let store = makeStore(snapshots)
        let base = URL(fileURLWithPath: path).deletingPathExtension().path
        guard renderPopup(store: store, path: base + "-stale.png", appearance: .aqua) else { return false }
        await store.refreshAll(force: true)
        guard renderPopup(store: store, path: path, appearance: .aqua),
              renderPopup(store: store, path: base + "-dark.png", appearance: .darkAqua) else { return false }
        let extraSnapshots = snapshots.map { snapshot in
            UsageSnapshot(provider: snapshot.provider, plan: snapshot.plan, windows: snapshot.windows + (0..<8).map { index in
                UsageWindow(id: "model-\(index)", name: "Additional model \(index)", usedPercent: Double(90 + index),
                            resetsAt: now.addingTimeInterval(86400), durationMinutes: 10080)
            }, fetchedAt: now)
        }
        let extraStore = makeStore(extraSnapshots)
        await extraStore.refreshAll(force: true)
        guard renderPopup(store: extraStore, path: base + "-extra.png", appearance: .aqua) else { return false }
        let errorStore = makeStore(snapshots, error: .expiredCredentials("Fixture provider"))
        await errorStore.refreshAll(force: true)
        guard renderPopup(store: errorStore, path: base + "-error.png", appearance: .aqua) else { return false }
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
        print("Provider artwork loaded: Claude \(MenuBarIcon.hasClaudeArtwork), OpenAI \(MenuBarIcon.hasOpenAIArtwork)")
        let image = NSImage(size: NSSize(width: 440, height: 100), flipped: false) { _ in
            NSColor.white.setFill(); NSBezierPath(rect: NSRect(x: 0,y: 0,width: 440,height: 100)).fill()
            for (index, values) in combinations.enumerated() {
                let states = zip([ProviderKind.claude,.codex], [values.0,values.1]).map { kind, used in
                    ProviderDisplayState(provider: kind, snapshot: used.map { value in
                        UsageSnapshot(provider: kind, plan: nil, windows: [UsageWindow(id: kind == .claude ? "claude-five_hour" : "fixture", name: "Fixture", usedPercent: value,
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
