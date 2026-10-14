import AppKit
import Foundation
import Network
import QuotaBarCore

@MainActor
final class UsageStore: ObservableObject {
    static let shared = UsageStore()
    @Published private(set) var states: [ProviderKind: ProviderDisplayState]
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastRefreshAt: Date?
    @Published private(set) var nextRefreshAt: [ProviderKind: Date] = [:]
    @Published private(set) var networkAvailable = true

    let preferences: AppPreferences
    private let providers: [any UsageProvider]
    private let notificationService = NotificationService()
    private let networkMonitor = NWPathMonitor()
    private var refreshLoop: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    private var started = false
    private var sleeping = false
    private var pendingRefresh = false
    private var failures: [ProviderKind: Int] = [:]
    private var rateLimitedUntil: [ProviderKind: Date] = [:]
    private var ledger: AlertLedger

    init(providers: [any UsageProvider] = [ClaudeUsageProvider(), CodexUsageProvider()],
         preferences: AppPreferences? = nil) {
        self.providers = providers
        self.preferences = preferences ?? AppPreferences()
        if let data = UserDefaults.standard.data(forKey: "alertLedger"),
           let saved = try? JSONDecoder().decode(AlertLedger.self, from: data) { ledger = saved }
        else { ledger = AlertLedger() }
        states = Dictionary(uniqueKeysWithValues: ProviderKind.allCases.map { kind in
            let cached = Self.loadCachedSnapshot(for: kind)
            return (kind, ProviderDisplayState(provider: kind, snapshot: cached,
                errorMessage: nil, isRefreshing: false, isStale: cached != nil))
        })
    }

    deinit {
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        refreshLoop?.cancel(); networkMonitor.cancel()
    }

    var orderedStates: [ProviderDisplayState] { [.claude, .codex].compactMap { states[$0] } }

    func start() {
        guard !started else { return }; started = true
        preferences.applyInitialLaunchAtLoginPreference()
        Task { await notificationService.requestAuthorization() }
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.sleeping = true }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.sleeping = false; await self?.refreshAll(force: true) }
        })
        networkMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self else { return }
                let recovered = !self.networkAvailable && path.status == .satisfied
                self.networkAvailable = path.status == .satisfied
                if recovered { await self.refreshAll(force: true) }
            }
        }
        networkMonitor.start(queue: DispatchQueue(label: "quotabar.network"))
        refreshLoop = Task { [weak self] in
            await self?.refreshAll(force: true)
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 20_000_000_000)
                guard !Task.isCancelled else { return }
                await self?.refreshAll(force: false)
            }
        }
    }

    func refreshIfStale() async {
        let needsRefresh = orderedStates.contains { state in
            guard let snapshot = state.snapshot else { return true }
            return state.hasStaleData() || Date().timeIntervalSince(snapshot.fetchedAt) > 60
        }
        if needsRefresh { await refreshAll(force: false) }
    }

    func refreshAll(force: Bool) async {
        guard !sleeping else { return }
        if isRefreshing { pendingRefresh = pendingRefresh || force; return }
        let now = Date()
        let selected = providers.filter { provider in
            if let until = rateLimitedUntil[provider.kind], until > now { return false }
            return force || (nextRefreshAt[provider.kind] ?? .distantPast) <= now
        }
        guard !selected.isEmpty else { return }
        if !networkAvailable {
            for provider in selected {
                states[provider.kind]?.isStale = states[provider.kind]?.snapshot != nil
                states[provider.kind]?.errorMessage = "Offline — waiting for the network"
            }
            return
        }
        isRefreshing = true
        defer {
            isRefreshing = false
            lastRefreshAt = Date()
            if pendingRefresh {
                pendingRefresh = false
                Task { await self.refreshAll(force: true) }
            }
        }
        for provider in selected { states[provider.kind]?.isRefreshing = true }
        await withTaskGroup(of: (ProviderKind, Result<UsageSnapshot, Error>).self) { group in
            for provider in selected {
                group.addTask {
                    do { return (provider.kind, .success(try await provider.fetch())) }
                    catch { return (provider.kind, .failure(error)) }
                }
            }
            for await (kind, result) in group {
                let previous = states[kind]?.snapshot
                switch result {
                case let .success(snapshot):
                    states[kind] = ProviderDisplayState(provider: kind, snapshot: snapshot,
                        errorMessage: nil, isRefreshing: false, isStale: false)
                    failures[kind] = 0; rateLimitedUntil[kind] = nil
                    nextRefreshAt[kind] = Date().addingTimeInterval(RefreshPolicy.interval(previous: previous, current: snapshot, now: Date()))
                    Self.cache(snapshot)
                    let alerts = ledger.take(previous: previous, current: snapshot,
                        thresholds: preferences.enabledThresholds, resetEnabled: preferences.notificationReset)
                    if let data = try? JSONEncoder().encode(ledger) { UserDefaults.standard.set(data, forKey: "alertLedger") }
                    for alert in alerts { await notificationService.send(alert) }
                case let .failure(error):
                    failures[kind, default: 0] += 1
                    let delay = RefreshPolicy.retryInterval(failures: failures[kind] ?? 1, error: error as? ProviderError)
                    nextRefreshAt[kind] = Date().addingTimeInterval(delay)
                    if case ProviderError.rateLimited = error { rateLimitedUntil[kind] = nextRefreshAt[kind] }
                    states[kind] = ProviderDisplayState(provider: kind, snapshot: previous,
                        errorMessage: (error as? LocalizedError)?.errorDescription ?? "Usage unavailable. Check provider login and permissions.",
                        isRefreshing: false, isStale: previous != nil)
                }
            }
        }
    }

    private static func cache(_ snapshot: UsageSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults.standard.set(data, forKey: "cachedSnapshot.\(snapshot.provider.rawValue)")
    }

    private static func loadCachedSnapshot(for provider: ProviderKind) -> UsageSnapshot? {
        guard let data = UserDefaults.standard.data(forKey: "cachedSnapshot.\(provider.rawValue)") else { return nil }
        return try? JSONDecoder().decode(UsageSnapshot.self, from: data)
    }
}
