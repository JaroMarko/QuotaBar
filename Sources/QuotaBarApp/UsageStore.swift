import AppKit
import Foundation
import QuotaBarCore

@MainActor
final class UsageStore: ObservableObject {
    static let shared = UsageStore()

    @Published private(set) var states: [ProviderKind: ProviderDisplayState]
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastRefreshAt: Date?

    let preferences: AppPreferences
    private let providers: [any UsageProvider]
    private let notificationService = NotificationService()
    private var refreshLoop: Task<Void, Never>?
    private var wakeObserver: NSObjectProtocol?
    private var started = false
    private var backoffUntil: [ProviderKind: Date] = [:]

    init(
        providers: [any UsageProvider] = [ClaudeUsageProvider(), CodexUsageProvider()],
        preferences: AppPreferences? = nil
    ) {
        self.providers = providers
        self.preferences = preferences ?? AppPreferences()
        var initial: [ProviderKind: ProviderDisplayState] = [:]
        for kind in ProviderKind.allCases {
            let cached = Self.loadCachedSnapshot(for: kind)
            initial[kind] = ProviderDisplayState(
                provider: kind,
                snapshot: cached,
                errorMessage: nil,
                isRefreshing: false,
                isStale: cached != nil
            )
        }
        states = initial
    }

    deinit {
        if let wakeObserver { NotificationCenter.default.removeObserver(wakeObserver) }
        refreshLoop?.cancel()
    }

    var orderedStates: [ProviderDisplayState] {
        [.claude, .codex].compactMap { states[$0] }
    }

    var menuBarText: String {
        let highest = orderedStates.compactMap { $0.snapshot?.highestUsedPercent }.max()
        return highest.map(UsageFormatting.percent) ?? "—"
    }

    func start() {
        guard !started else { return }
        started = true
        preferences.applyInitialLaunchAtLoginPreference()
        Task { await notificationService.requestAuthorization() }

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.refreshAll(force: false) }
        }

        refreshLoop = Task { [weak self] in
            guard let self else { return }
            await self.refreshAll(force: true)
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 300_000_000_000)
                guard !Task.isCancelled else { return }
                await self.refreshAll(force: false)
            }
        }
    }

    func refreshIfStale() async {
        guard let lastRefreshAt else {
            await refreshAll(force: true)
            return
        }
        if Date().timeIntervalSince(lastRefreshAt) > 60 {
            await refreshAll(force: false)
        }
    }

    func refreshAll(force: Bool) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        for kind in ProviderKind.allCases {
            states[kind]?.isRefreshing = true
        }

        await withTaskGroup(of: (ProviderKind, Result<UsageSnapshot, Error>).self) { group in
            for provider in providers {
                if !force, let until = backoffUntil[provider.kind], until > Date() {
                    states[provider.kind]?.isRefreshing = false
                    continue
                }
                group.addTask {
                    do { return (provider.kind, .success(try await provider.fetch())) }
                    catch { return (provider.kind, .failure(error)) }
                }
            }

            for await (kind, result) in group {
                let previous = states[kind]?.snapshot
                switch result {
                case let .success(snapshot):
                    states[kind] = ProviderDisplayState(
                        provider: kind,
                        snapshot: snapshot,
                        errorMessage: nil,
                        isRefreshing: false,
                        isStale: false
                    )
                    backoffUntil[kind] = nil
                    Self.cache(snapshot)
                    let alerts = AlertEngine.events(
                        previous: previous,
                        current: snapshot,
                        enabledThresholds: preferences.enabledThresholds,
                        resetEnabled: preferences.notificationReset
                    )
                    for alert in alerts { await notificationService.send(alert) }
                case let .failure(error):
                    if case ProviderError.rateLimited = error {
                        backoffUntil[kind] = Date().addingTimeInterval(600)
                    }
                    states[kind] = ProviderDisplayState(
                        provider: kind,
                        snapshot: previous,
                        errorMessage: (error as? LocalizedError)?.errorDescription ?? "Usage is currently unavailable.",
                        isRefreshing: false,
                        isStale: previous != nil
                    )
                }
            }
        }

        isRefreshing = false
        lastRefreshAt = Date()
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
