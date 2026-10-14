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

    @Published private(set) var history = UsageHistory()
    @Published private(set) var historyError: String?
    private let historyPersistence: HistoryPersistence
    private let defaults: UserDefaults
    private var historyWritable = true

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
    private let activityProbe: @MainActor (ProviderKind) -> Bool?
    private var presence: [ProviderKind: Bool] = [:]

    init(providers: [any UsageProvider] = [ClaudeUsageProvider(), CodexUsageProvider()],
         preferences: AppPreferences? = nil, defaults: UserDefaults = .standard,
         historyPersistence: HistoryPersistence = HistoryPersistence(),
         activityProbe: @escaping @MainActor (ProviderKind) -> Bool? = { ProviderActivityProbe.isRunning($0) }) {
        self.providers = providers
        self.activityProbe = activityProbe
        self.defaults = defaults
        self.historyPersistence = historyPersistence
        self.preferences = preferences ?? AppPreferences(defaults: defaults)
        if let data = defaults.data(forKey: "alertLedger"),
           let saved = try? JSONDecoder().decode(AlertLedger.self, from: data) { ledger = saved }
        else { ledger = AlertLedger() }
        states = Dictionary(uniqueKeysWithValues: ProviderKind.allCases.map { kind in
            let cached = Self.loadCachedSnapshot(for: kind, defaults: defaults)
            return (kind, ProviderDisplayState(provider: kind, snapshot: cached,
                errorMessage: nil, isRefreshing: false, isStale: cached != nil))
        })
        // Keep the server-error pause across app updates/restarts as well.
        for kind in ProviderKind.allCases {
            let key = "rateLimitedUntil.\(kind.rawValue)"
            if let until = defaults.object(forKey: key) as? Date,
               until > Date(), until.timeIntervalSinceNow <= 600 {
                rateLimitedUntil[kind] = until
                nextRefreshAt[kind] = until
                let error = ProviderError.rateLimited(kind.displayName)
                states[kind]?.errorMessage = error.errorDescription
                states[kind]?.errorHelp = error.recoveryExplanation
            } else { defaults.removeObject(forKey: key) }
        }
        synchronizeActivity()
    }

    deinit {
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        refreshLoop?.cancel(); networkMonitor.cancel()
    }

    var orderedStates: [ProviderDisplayState] { [.claude, .codex].compactMap { states[$0] } }

    private func synchronizeActivity() {
        for kind in ProviderKind.allCases {
            let previous = presence[kind]
            presence[kind] = activityProbe(kind)
            guard let running = presence[kind] else {
                states[kind]?.isInactive = false
                states[kind]?.isStale = states[kind]?.snapshot != nil
                states[kind]?.errorMessage = "Could not check whether \(kind.displayName) is running."
                states[kind]?.errorHelp = "Application activity could not be verified. Quota checks are paused until detection succeeds."
                continue
            }
            states[kind]?.isInactive = !running
            if !running {
                states[kind]?.isRefreshing = false
                states[kind]?.isStale = states[kind]?.snapshot != nil
                states[kind]?.errorMessage = nil
                states[kind]?.errorHelp = nil
            } else if previous != true {
                // Resume promptly after launch without bypassing a server429 pause.
                if let until = rateLimitedUntil[kind], until > Date() {
                    nextRefreshAt[kind] = until
                    let error = ProviderError.rateLimited(kind.displayName)
                    states[kind]?.errorMessage = error.errorDescription
                    states[kind]?.errorHelp = error.recoveryExplanation
                } else {
                    nextRefreshAt[kind] = .distantPast
                    states[kind]?.errorMessage = nil
                    states[kind]?.errorHelp = nil
                }
            }
        }
    }

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
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      ProviderKind.allCases.contains(where: { ProviderActivityProbe.bundleIDs(for: $0).contains(app.bundleIdentifier ?? "") }) else { return }
                Task { @MainActor in await self?.refreshAll(force: false) }
            })
        }
        networkMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self else { return }
                let recovered = !self.networkAvailable && path.status == .satisfied
                self.networkAvailable = path.status == .satisfied
                if !self.networkAvailable {
                    for kind in ProviderKind.allCases where self.states[kind]?.isInactive != true {
                        self.states[kind]?.isStale = self.states[kind]?.snapshot != nil
                        self.states[kind]?.errorMessage = "Offline — waiting for the network"
                        self.states[kind]?.errorHelp = ProviderError.networkUnavailable(kind.displayName).recoveryExplanation
                    }
                }
                if recovered { await self.refreshAll(force: true) }
            }
        }
        networkMonitor.start(queue: DispatchQueue(label: "quotabar.network"))
        refreshLoop = Task { [weak self] in
            guard let self else { return }
            do { self.history = try await self.historyPersistence.load() }
            catch { self.historyError = "History could not be loaded; existing file retained."; self.historyWritable = false }
            await self.refreshAll(force: true)
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 20_000_000_000)
                guard !Task.isCancelled else { return }
                await self.refreshAll(force: false)
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
        synchronizeActivity()
        guard !sleeping else { return }
        if isRefreshing { pendingRefresh = pendingRefresh || force; return }
        let now = Date()
        let selected = providers.filter { provider in
            if presence[provider.kind] != true { return false }
            if let until = rateLimitedUntil[provider.kind], until > now { return false }
            return force || (nextRefreshAt[provider.kind] ?? .distantPast) <= now
        }
        guard !selected.isEmpty else { return }
        if !networkAvailable {
            for provider in selected {
                states[provider.kind]?.isStale = states[provider.kind]?.snapshot != nil
                states[provider.kind]?.errorMessage = "Offline — waiting for the network"
                states[provider.kind]?.errorHelp = ProviderError.networkUnavailable(provider.kind.displayName).recoveryExplanation
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
                synchronizeActivity()
                let inactive = presence[kind] == false
                let unverified = presence[kind] == nil
                let previous = states[kind]?.snapshot
                switch result {
                case let .success(snapshot):
                    states[kind] = ProviderDisplayState(provider: kind, snapshot: snapshot,
                        errorMessage: nil, isRefreshing: false, isStale: inactive || unverified, isInactive: inactive)
                    failures[kind] = 0; rateLimitedUntil[kind] = nil
                    defaults.removeObject(forKey: "rateLimitedUntil.\(kind.rawValue)")
                    nextRefreshAt[kind] = Date().addingTimeInterval(RefreshPolicy.interval(previous: previous, current: snapshot, now: Date()))
                    Self.cache(snapshot, defaults: defaults)
                    history.append(snapshot)
                    if historyWritable {
                        do { try await historyPersistence.save(history); historyError = nil }
                        catch { historyError = "Local history could not be saved." }
                    }
                    synchronizeActivity()
                    if presence[kind] != true { continue }
                    let alerts = ledger.take(previous: previous, current: snapshot,
                        thresholds: preferences.enabledThresholds, resetEnabled: preferences.notificationReset)
                    if let data = try? JSONEncoder().encode(ledger) { defaults.set(data, forKey: "alertLedger") }
                    for alert in alerts {
                        synchronizeActivity()
                        guard presence[kind] == true else { break }
                        await notificationService.send(alert)
                    }
                case let .failure(error):
                    failures[kind, default: 0] += 1
                    let delay = RefreshPolicy.retryInterval(failures: failures[kind] ?? 1, error: error as? ProviderError)
                    nextRefreshAt[kind] = Date().addingTimeInterval(delay)
                    if case ProviderError.rateLimited = error {
                        rateLimitedUntil[kind] = nextRefreshAt[kind]
                        defaults.set(nextRefreshAt[kind], forKey: "rateLimitedUntil.\(kind.rawValue)")
                    }
                    states[kind] = ProviderDisplayState(provider: kind, snapshot: previous,
                        errorMessage: (error as? LocalizedError)?.errorDescription ?? "Usage unavailable. Check provider login and permissions.",
                        isRefreshing: false, isStale: previous != nil,
                        errorHelp: (error as? ProviderError)?.recoveryExplanation, isInactive: inactive)
                    if inactive || unverified { synchronizeActivity() }
                }
            }
        }
    }

    func clearHistory() async {
        let empty = UsageHistory()
        do {
            try await historyPersistence.save(empty)
            history = empty; historyError = nil; historyWritable = true
        } catch { historyError = "Local history could not be cleared." }
    }

    private static func cache(_ snapshot: UsageSnapshot, defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: "cachedSnapshot.\(snapshot.provider.rawValue)")
    }

    private static func loadCachedSnapshot(for provider: ProviderKind, defaults: UserDefaults) -> UsageSnapshot? {
        guard let data = defaults.data(forKey: "cachedSnapshot.\(provider.rawValue)") else { return nil }
        return try? JSONDecoder().decode(UsageSnapshot.self, from: data)
    }
}
