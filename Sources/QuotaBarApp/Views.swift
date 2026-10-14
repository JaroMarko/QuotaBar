import AppKit
import Charts
import QuotaBarCore
import SwiftUI

struct QuotaBarMenuView: View {
    @ObservedObject var store: UsageStore
    @State private var showingAbout = false
    @State private var confirmingClearHistory = false

    var body: some View {
        VStack(spacing: 12) {
            header
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(store.orderedStates) { state in
                        ProviderCard(state: state, history: store.history)
                    }
                }
            }
            .frame(maxHeight: 470)
            capacityOverview
            if let error = store.historyError { Text(error).font(.caption2).foregroundStyle(.orange) }
            footer
        }
        .padding(14)
        .frame(width: 410)
        .task { await store.refreshIfStale() }
        .sheet(isPresented: $showingAbout) { AboutView() }
        .confirmationDialog("Clear local usage history?", isPresented: $confirmingClearHistory) {
            Button("Clear history", role: .destructive) { Task { await store.clearHistory() } }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Recorded percentages and reset times will be removed. Provider credentials are unaffected.") }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("QuotaBar")
                    .font(.headline)
                Text(store.networkAvailable ? lastUpdatedText : "Offline — showing last known data")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                Task { await store.refreshAll(force: true) }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .disabled(store.isRefreshing)
            .help("Refresh usage")
            .accessibilityLabel("Refresh usage")
        }
    }

    private var footer: some View {
        HStack(spacing: 14) {
            Button { QuotaBarDelegate.shared?.showSettings() } label: {
                Label("Settings", systemImage: "gearshape")
            }
            .buttonStyle(.borderless)
            Button("About") { showingAbout = true }
                .buttonStyle(.borderless)
            Button { confirmingClearHistory = true } label: { Image(systemName: "trash") }
                .help("Clear local usage history")
                .buttonStyle(.borderless)
            Spacer()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.borderless)
        }
        .font(.caption)
    }

    private var capacityOverview: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Available headroom").font(.caption.weight(.semibold))
            ForEach(store.orderedStates) { state in
                HStack {
                    Image(systemName: state.provider.symbolName)
                    Text(state.provider.displayName)
                    Spacer()
                    if let used = state.meterValue() {
                        Text("\(UsageFormatting.percent(100 - used)) remaining in tightest reported window")
                    } else { Text("Unconfirmed") }
                }.font(.caption2).foregroundStyle(.secondary)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var lastUpdatedText: String {
        guard let date = store.lastRefreshAt else { return "Waiting for first refresh" }
        return "Last check \(date.formatted(date: .omitted, time: .shortened))"
    }
}

struct ProviderCard: View {
    let state: ProviderDisplayState
    let history: UsageHistory

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: state.provider.symbolName)
                    .foregroundStyle(accent)
                Text(state.provider.displayName)
                    .font(.headline)
                if let plan = state.snapshot?.plan, !plan.isEmpty {
                    Text(plan)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(accent.opacity(0.12), in: Capsule())
                        .foregroundStyle(accent)
                }
                Spacer()
                if state.isRefreshing { ProgressView().controlSize(.small) }
                if state.hasStaleData() {
                    Image(systemName: "clock.badge.exclamationmark")
                        .foregroundStyle(.secondary)
                        .help("Showing last known usage")
                }
            }

            if let snapshot = state.snapshot {
                ForEach(snapshot.windows) { window in
                    UsageWindowRow(window: window, isStale: state.hasStaleData(), isTightest: window.id == snapshot.windows.max(by: { $0.clampedUsedPercent < $1.clampedUsedPercent })?.id, samples: history.series(for: snapshot, window: window))
                    if window.id != snapshot.windows.last?.id {
                        Divider().opacity(0.55)
                    }
                }
            }

            if let snapshot = state.snapshot {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Measured \(snapshot.fetchedAt.formatted(date: .abbreviated, time: .standard))")
                    Text(snapshot.source ?? "Legacy cached measurement")
                    Text(snapshot.account ?? "Account identity not supplied by this source")
                    if state.hasStaleData() { Text("Last known data — current quota is unconfirmed").foregroundStyle(.orange) }
                }
                .font(.caption2).foregroundStyle(.secondary)
            }
            if let error = state.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if state.snapshot == nil && !state.isRefreshing {
                Text("No usage data yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.75)
        )
    }

    private var accent: Color {
        state.provider == .claude ? .orange : .indigo
    }
}

struct UsageWindowRow: View {
    let window: UsageWindow
    var isStale = false
    var isTightest = false
    var samples: [UsageSample] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(window.name)
                    .font(.subheadline.weight(.medium))
                if isTightest { Image(systemName: "gauge.with.dots.needle.67percent").help("Most-used reported quota window") }
                Spacer()
                Text("\(UsageFormatting.percent(window.clampedUsedPercent)) used")
                    .font(.caption.monospacedDigit().weight(.semibold))
            }
            ProgressView(value: window.clampedUsedPercent, total: 100)
                .tint(progressColor)
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
            if !isStale, let forecast = UsageForecast.estimate(samples: samples, now: Date()) {
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

    private var progressColor: Color {
        switch window.clampedUsedPercent {
        case 100...: .red
        case 90...: .orange
        case 75...: .yellow
        default: .indigo
        }
    }
}

struct SettingsView: View {
    @ObservedObject var preferences: AppPreferences

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch QuotaBar at login", isOn: $preferences.launchAtLogin)
                Text("Adaptive refresh: every 1–5 minutes, on wake and network recovery. Errors slow retries.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let error = preferences.launchAtLoginError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }
            Section("Notifications") {
                Toggle("At 75% used", isOn: $preferences.notification75)
                Toggle("At 90% used", isOn: $preferences.notification90)
                Toggle("At 100% used", isOn: $preferences.notification100)
                Toggle("When a usage window resets", isOn: $preferences.notificationReset)
            }
            Section("Privacy") {
                Text("QuotaBar reads existing Codex and Claude Code sessions only when refreshing. Credentials are never stored or logged. No analytics or telemetry are collected.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(8)
        .frame(width: 460, height: 390)
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
            Text("A private, local-first meter for Claude and Codex subscription usage. No analytics, telemetry, or credential storage.")
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
