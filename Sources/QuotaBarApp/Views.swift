import AppKit
import Charts
import QuotaBarCore
import SwiftUI

struct QuotaBarMenuView: View {
    @ObservedObject var store: UsageStore
    var refreshOnAppear = true
    @State private var showingAbout = false
    @State private var confirmingClearHistory = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            VStack(spacing: 8) {
                if store.orderedStates.isEmpty { Text("Sledovanie je vypnuté.").foregroundStyle(.secondary) }
                else { header }
                ViewThatFits(in: .vertical) {
                    providerCards(at: context.date).fixedSize(horizontal: false, vertical: true)
                    ScrollView { providerCards(at: context.date) }
                }
                .frame(maxHeight: 340)
                if !store.networkAvailable { Text("Offline · posledné meranie").font(.caption).foregroundStyle(.secondary) }
                if let error = store.historyError {
                    Text(error).font(.caption2).foregroundStyle(.orange)
                }
                Divider()
                footer
            }
            .padding(12)
            .frame(width: 360)
        }
        .task { if refreshOnAppear { await store.refreshIfStale() } }
        .sheet(isPresented: $showingAbout) { AboutView() }
        .confirmationDialog("Clear local usage history?", isPresented: $confirmingClearHistory) {
            Button("Clear history", role: .destructive) { Task { await store.clearHistory() } }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Recorded percentages and reset times will be removed. Provider credentials are unaffected.") }
    }

    private func providerCards(at now: Date) -> some View {
        VStack(spacing: 0) {
            ForEach(store.orderedStates) { state in
                ProviderCard(state: state, now: now, nextRetry: store.nextRefreshAt[state.provider])
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Kvóta").frame(maxWidth: .infinity, alignment: .leading)
            Text("Zostáva").frame(width: QuotaSummaryRow.percentWidth, alignment: .trailing)
            Text("Reset o").frame(width: QuotaSummaryRow.resetWidth, alignment: .trailing)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.secondary)
        .padding(.bottom, 4)
        .overlay(alignment: .bottom) { Divider() }
    }

    private var footer: some View {
        HStack(spacing: 14) {
            Button { QuotaBarDelegate.shared?.showSettings() } label: {
                Label("Nastavenia", systemImage: "gearshape")
            }.buttonStyle(.borderless)
            Button { Task { await store.refreshAll(force: true) } } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.borderless).disabled(store.isRefreshing || store.orderedStates.isEmpty)
                .help(lastUpdatedText).accessibilityLabel("Obnoviť kvóty")
            Button("O aplikácii") { showingAbout = true }.buttonStyle(.borderless)
            Button { confirmingClearHistory = true } label: { Image(systemName: "trash") }
                .help("Clear local usage history")
                .accessibilityLabel("Clear local usage history")
                .buttonStyle(.borderless)
            Spacer()
            Button("Ukončiť") { NSApplication.shared.terminate(nil) }.buttonStyle(.borderless)
        }.font(.caption)
    }

    private var lastUpdatedText: String {
        if store.orderedStates.allSatisfy(\.isInactive) { return "Sledovanie je pozastavené" }
        guard let date = store.lastRefreshAt else { return "Čaká sa na prvé meranie" }
        return "Posledná kontrola \(date.formatted(date: .omitted, time: .shortened))"
    }
}

private struct ProviderCard: View {
    let state: ProviderDisplayState
    let now: Date
    var nextRetry: Date?
    @Environment(\.colorScheme) private var scheme

    private var snapshot: UsageSnapshot? {
        state.isInactive && state.provider != .gemini ? nil : state.snapshot
    }

    private var windows: [UsageWindow] {
        (snapshot?.windows ?? []).filter { window in
            state.provider != .codex || !(window.name.hasSuffix("5-hour session") || window.durationMinutes == 300)
        }.sorted { lhs, rhs in
            let left = lhs.durationMinutes ?? .max, right = rhs.durationMinutes ?? .max
            if left != right { return left < right }
            if state.provider == .gemini {
                let leftShared = lhs.name.hasPrefix("Gemini Models · ")
                let rightShared = rhs.name.hasPrefix("Gemini Models · ")
                if leftShared != rightShared { return leftShared }
            }
            return lhs.id < rhs.id
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Button { QuotaBarDelegate.shared?.showDetails(for: state.provider) } label: {
                    HStack(spacing: 4) {
                        Text(state.provider == .gemini ? "Gemini" : state.provider.displayName)
                            .font(.subheadline.weight(.semibold))
                        Image(systemName: "chevron.right").font(.system(size: 8, weight: .semibold)).foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Detail · \(state.provider.displayName)")
                Spacer()
                if state.isRefreshing { ProgressView().controlSize(.mini) }
            }
            if windows.isEmpty {
                Text(state.isInactive ? "Sledovanie pozastavené" : state.isRefreshing ? "Načítava sa…" : "Bez dostupnej kvóty")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(windows) { window in
                    QuotaSummaryRow(window: window, now: now,
                                    accent: Color(nsColor: MenuBarIcon.providerColour(state.provider, dark: scheme == .dark)))
                }
            }
            if let snapshot, state.isInactive || state.hasStaleData(at: now) || state.errorMessage != nil {
                Label("Posledné meranie · \(snapshot.fetchedAt.formatted(date: .abbreviated, time: .shortened))", systemImage: "clock")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            if !state.isInactive, let error = state.errorMessage {
                ProviderErrorNotice(state: state, message: error, nextRetry: nextRetry)
            } else if let notice = snapshot?.notice {
                Text(notice).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 7)
    }
}

private struct InactiveProviderNotice: View {
    let provider: ProviderKind
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Label("Vypnutá", systemImage: "power").font(.subheadline.weight(.medium))
            Text(provider == .gemini ? "Spusti agy a sledovanie sa obnoví." : provider == .claude ? "Spusti lokálnu kartu Code v Claude alebo Claude Code s QuotaBar rozšírením." : "Spusti Codex alebo ChatGPT a sledovanie sa obnoví.")
                .font(.caption2)
        }.foregroundStyle(.secondary)
    }
}

private struct ProviderErrorNotice: View {
    let state: ProviderDisplayState
    let message: String
    var nextRetry: Date? = nil
    @State private var showingHelp = false

    private var explanation: String {
        state.errorHelp ?? "Current usage is unavailable. Shown percentages, if present, are last known values. QuotaBar will retry automatically."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .top, spacing: 6) {
                Label(state.hasStaleData() ? "Last known usage · \(message)" : message, systemImage: "exclamationmark.triangle.fill")
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button { showingHelp.toggle() } label: {
                    Image(systemName: "questionmark.circle")
                }
                .buttonStyle(.borderless).help(explanation)
                .accessibilityLabel("Explain \(state.provider.displayName) quota error")
                .popover(isPresented: $showingHelp) {
                    Text(explanation).font(.callout).padding(14).frame(width: 300)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .foregroundStyle(.orange)
            if let nextRetry {
                Text(nextRetry > Date() ? "Next attempt: \(nextRetry.formatted(date: .omitted, time: .shortened))" : "Waiting for the next automatic attempt")
                    .foregroundStyle(.secondary)
            }
        }.font(.caption2)
    }
}

private struct QuotaSummaryRow: View {
    static let percentWidth: CGFloat = 66
    static let resetWidth: CGFloat = 100
    let window: UsageWindow
    let now: Date
    let accent: Color

    private var percent: String {
        window.remainingPercent.formatted(.number.locale(Locale(identifier: "sk_SK")).precision(.fractionLength(0...2))) + " %"
    }

    private var title: String {
        window.name
            .replacingOccurrences(of: "Gemini Models · ", with: "")
            .replacingOccurrences(of: "Gemini 4 Argon Weekly Limit", with: "Argon · 7 dní")
            .replacingOccurrences(of: " Limit Remaining", with: "")
            .replacingOccurrences(of: " Limit", with: "")
            .replacingOccurrences(of: "5-hour session", with: "5 hodín")
            .replacingOccurrences(of: "Five Hour", with: "5 hodín")
            .replacingOccurrences(of: "Weekly", with: "7 dní")
    }

    private var countdown: String {
        guard let reset = window.resetsAt else { return "čas neznámy" }
        let seconds = reset.timeIntervalSince(now)
        guard seconds > 0 else { return "čaká na potvrdenie" }
        let minutes = Int(ceil(seconds / 60))
        let hours = minutes / 60, days = hours / 24
        if days > 0 {
            let unit = days == 1 ? "deň" : days < 5 ? "dni" : "dní"
            return "\(days) \(unit) \(hours % 24) h"
        }
        return hours > 0 ? "\(hours) h \(minutes % 60) min" : "\(minutes) min"
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(title).font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
            GeometryReader { geometry in
                Capsule().fill(.quaternary)
                    .overlay(alignment: .leading) {
                        Capsule().fill(accent)
                            .frame(width: geometry.size.width * window.remainingPercent / 100)
                    }
            }
            .frame(width: 48, height: 4)
            Text(percent).fontWeight(.semibold)
                .frame(width: Self.percentWidth, alignment: .trailing)
            Text(countdown)
                .frame(width: Self.resetWidth, alignment: .trailing)
        }
        .font(.callout.monospacedDigit())
        .padding(.vertical, 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(window.name)
        .accessibilityValue("Zostáva \(percent). Reset: \(countdown)")
        .help(window.name + (window.resetsAt.map { " · Reset " + $0.formatted() } ?? ""))
    }
}

struct ProviderDetailsView: View {
    let state: ProviderDisplayState
    let history: UsageHistory

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { _ in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("\(state.provider.displayName) details").font(.title2.weight(.semibold))
                    if state.isInactive {
                        InactiveProviderNotice(provider: state.provider)
                    }
                    if (!state.isInactive || state.provider == .gemini), let snapshot = state.snapshot {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Measured \(snapshot.fetchedAt.formatted(date: .abbreviated, time: .standard))")
                            Text(snapshot.source ?? "Legacy cached measurement")
                            Text(snapshot.account ?? (snapshot.accountID == nil ? "Account identity not supplied by this source" : "Account identified by this source"))
                            if let notice = snapshot.notice { Label(notice, systemImage: "info.circle") }
                            if state.hasStaleData() {
                                Text("Last known data — current quota is unconfirmed").foregroundStyle(.orange)
                            }
                        }.font(.caption).foregroundStyle(.secondary)
                        ForEach(snapshot.windows) { window in
                            UsageWindowDetailRow(window: window, isStale: state.hasStaleData(), allowsForecast: state.provider != .claude, isMeterWindow: window.id == snapshot.meterWindow?.id, samples: history.series(for: snapshot, window: window))
                            Divider()
                        }
                    } else if !state.isInactive {
                        Text("No usage data yet.").foregroundStyle(.secondary)
                    }
                    if !state.isInactive, let error = state.errorMessage {
                        ProviderErrorNotice(state: state, message: error)
                    }
                }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private func usageColor(_ percent: Double) -> Color {
    switch percent {
    case 100...: .red
    case 90...: .orange
    case 75...: .yellow
    default: .indigo
    }
}

struct UsageWindowDetailRow: View {
    let window: UsageWindow
    var isStale = false
    var allowsForecast = true
    var isMeterWindow = false
    var samples: [UsageSample] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(window.name)
                    .font(.subheadline.weight(.medium))
                if isMeterWindow { Image(systemName: "gauge.with.dots.needle.67percent").help("Shown in the menu bar ring") }
                Spacer()
                Text("\(UsageFormatting.percent(window.clampedUsedPercent)) used")
                    .font(.caption.monospacedDigit().weight(.semibold))
            }
            ProgressView(value: window.clampedUsedPercent, total: 100)
                .tint(usageColor(window.clampedUsedPercent))
                .accessibilityLabel("\(window.name) usage")
                .accessibilityValue("\(UsageFormatting.percent(window.clampedUsedPercent)) used, \(UsageFormatting.percent(window.remainingPercent)) remaining")
            HStack {
                Text("\(UsageFormatting.percent(window.remainingPercent)) remaining")
                Spacer()
                Text(UsageFormatting.countdown(to: window.resetsAt))
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .monospacedDigit()
            if let reset = window.resetsAt {
                Text("Reset: \(reset.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            if allowsForecast, !isStale, let forecast = UsageForecast.estimate(samples: samples, now: Date()) {
                Text(forecast.estimatedExhaustion.map { "Estimated exhaustion: \($0.formatted(date: .omitted, time: .shortened))" }
                     ?? "At recent pace: no projected exhaustion before reset")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            DisclosureGroup("Current window history") {
                if samples.count >= 2 {
                    Chart(Array(samples.suffix(96))) { sample in
                        LineMark(x: .value("Time", sample.measuredAt), y: .value("Used", sample.usedPercent), series: .value("Series", "Used"))
                            .foregroundStyle(.indigo)
                        if let guide = UsageForecast.evenUsePercent(window: window, at: sample.measuredAt) {
                            LineMark(x: .value("Time", sample.measuredAt), y: .value("Even use", guide), series: .value("Series", "Even use"))
                                .foregroundStyle(.secondary).lineStyle(StrokeStyle(lineWidth: 1, dash: [3,3]))
                        }
                    }
                    .chartYScale(domain: 0...100).frame(height: 85)
                    Text("Solid: measured usage. Dashed: even use over the window.")
                        .font(.caption2).foregroundStyle(.secondary)
                } else {
                    Text("History builds from successful measurements with a known reset.").font(.caption2).foregroundStyle(.secondary)
                }
            }.font(.caption2)
        }
        .opacity(isStale ? 0.55 : 1)
    }

}

struct SettingsView: View {
    @ObservedObject var preferences: AppPreferences
    let setMonitoring: (ProviderKind, Bool) -> Void
    @State private var sendingTest = false
    @State private var testMessage: String?

    var body: some View {
        Form {
            Section("Sledované aplikácie") {
                ForEach(ProviderKind.allCases) { provider in
                    Toggle(provider.displayName, isOn: Binding(
                        get: { preferences.enabledProviders.contains(provider) },
                        set: { setMonitoring(provider, $0) }
                    ))
                }
            }
            Section("Horná lišta") {
                Picker("Zobrazenie", selection: Binding(get: { preferences.effectiveMode }, set: { preferences.menuBarMode = $0 })) {
                    ForEach(preferences.availableModes) { mode in Text(mode.title).tag(mode) }
                }
                if preferences.effectiveMode.hasCenterMark {
                    Toggle("Zobraziť Q v strede kruhov", isOn: $preferences.showsCenterMark)
                }
                Text(preferences.effectiveMode.explanation(for: preferences.enabledProviders)).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section("General") {
                Toggle("Launch QuotaBar at login", isOn: $preferences.launchAtLogin)
                Text("Claude: local reads every 20 seconds; OAuth fallback at most every 5 minutes. Codex and Gemini check every 1–5 minutes while active.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let error = preferences.launchAtLoginError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }
            Section("Notifications") {
                Text("Claude automatic alerts and forecasts are paused until account identity is verified across its two sources. Gemini alerts use the account identified by agy.").font(.caption).foregroundStyle(.secondary)
                Toggle("At 75% used", isOn: $preferences.notification75)
                Toggle("At 90% used", isOn: $preferences.notification90)
                Toggle("At 100% used", isOn: $preferences.notification100)
                Toggle("When a usage window resets", isOn: $preferences.notificationReset)
                Button(sendingTest ? "Sending…" : "Send test notification") {
                    sendingTest = true
                    testMessage = nil
                    Task {
                        testMessage = await NotificationService().sendTest()
                        sendingTest = false
                    }
                }.disabled(sendingTest)
                if let testMessage {
                    Text(testMessage).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Section("Privacy") {
                Text("Claude prefers session.usage; an experimental OAuth fallback checks usage when local data is missing or over 5 minutes old. HTTP 429 pauses OAuth for 15–60 minutes. Existing Claude/Codex logins are read without storing or refreshing credentials. No analytics or telemetry.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(8)
        .frame(width: 460, height: 650)
    }
}

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.bar.fill")
                .font(.system(size: 42))
                .foregroundStyle(.indigo)
            Text("QuotaBar")
                .font(.title2.weight(.semibold))
            Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development")")
                .foregroundStyle(.secondary)
            Text("A private, local-first meter for Claude, Codex and Gemini subscription usage. No analytics, telemetry, or credential storage.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 300)
            Button("Close") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(28)
        .frame(width: 360, height: 260)
    }
}
