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
        TimelineView(.periodic(from: .now, by: 60)) { _ in
            VStack(spacing: 10) {
                header
                ForEach(store.orderedStates) { state in
                    ProviderCard(state: state)
                }
                Text("Menu bar shows usage: Claude — 5-hour session; Codex — most-used quota window.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let error = store.historyError {
                    Text(error).font(.caption2).foregroundStyle(.orange)
                }
                Divider()
                footer
            }
            .padding(14)
            .frame(width: 410)
        }
        .task { if refreshOnAppear { await store.refreshIfStale() } }
        .sheet(isPresented: $showingAbout) { AboutView() }
        .confirmationDialog("Clear local usage history?", isPresented: $confirmingClearHistory) {
            Button("Clear history", role: .destructive) { Task { await store.clearHistory() } }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Recorded percentages and reset times will be removed. Provider credentials are unaffected.") }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("QuotaBar").font(.headline)
                Text(store.networkAvailable ? lastUpdatedText : "Offline — last known data")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button { Task { await store.refreshAll(force: true) } } label: {
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
            }.buttonStyle(.borderless)
            Button("About") { showingAbout = true }.buttonStyle(.borderless)
            Button { confirmingClearHistory = true } label: { Image(systemName: "trash") }
                .help("Clear local usage history")
                .accessibilityLabel("Clear local usage history")
                .buttonStyle(.borderless)
            Spacer()
            Button("Quit") { NSApplication.shared.terminate(nil) }.buttonStyle(.borderless)
        }.font(.caption)
    }

    private var lastUpdatedText: String {
        guard let date = store.lastRefreshAt else { return "Waiting for first refresh" }
        return "Last check \(date.formatted(date: .omitted, time: .shortened))"
    }
}

struct ProviderCard: View {
    let state: ProviderDisplayState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: state.provider.symbolName).foregroundStyle(accent)
                Text(state.provider.displayName).font(.headline)
                if let plan = state.snapshot?.plan, !plan.isEmpty {
                    Text(plan).font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                if state.isRefreshing { ProgressView().controlSize(.small) }
                Button(detailLabel) { QuotaBarDelegate.shared?.showDetails(for: state.provider) }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .foregroundStyle(.tint)
                    .accessibilityLabel("\(state.provider.displayName) usage details")
            }
            if let snapshot = state.snapshot {
                HStack(alignment: .top, spacing: 8) {
                    ForEach(overviewWindows) { window in
                        UsageWindowTile(window: window, isMeterWindow: window.id == snapshot.meterWindow?.id)
                    }
                }
                if state.provider == .claude && snapshot.meterWindow == nil {
                    Text("5-hour quota unavailable — ring unconfirmed").font(.caption2).foregroundStyle(.orange)
                }
                if state.hasStaleData() && state.errorMessage == nil {
                    Label("Last known usage — current quota unconfirmed", systemImage: "clock.badge.exclamationmark")
                        .font(.caption2).foregroundStyle(.orange)
                }
            }
            if let error = state.errorMessage {
                Label(state.hasStaleData() ? "Last known usage · \(error)" : error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            } else if state.snapshot == nil {
                Text(state.isRefreshing ? "Checking usage…" : "No usage data yet.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(nsColor: .separatorColor), lineWidth: 0.75))
    }

    // Keep shared quotas visible, and include the ring's window if model-specific.
    // Other model limits remain available in Details without growing the popover.
    private var overviewWindows: [UsageWindow] {
        guard let snapshot = state.snapshot else { return [] }
        var windows = Array(snapshot.windows.prefix(2))
        if let meter = snapshot.meterWindow, !windows.contains(where: { $0.id == meter.id }) {
            windows.append(meter)
        }
        return windows
    }

    private var detailLabel: String {
        let extra = (state.snapshot?.windows.count ?? 0) - overviewWindows.count
        return extra > 0 ? "Details (+\(extra))" : "Details"
    }

    private var accent: Color { state.provider == .claude ? .orange : .indigo }
}

struct UsageWindowTile: View {
    let window: UsageWindow
    let isMeterWindow: Bool

    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                Circle().stroke(.quaternary, lineWidth: 4)
                Circle().trim(from: 0, to: window.clampedUsedPercent / 100)
                    .stroke(usageColor(window.clampedUsedPercent), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text(UsageFormatting.percent(window.clampedUsedPercent))
                        .font(.system(size: 14, weight: .semibold, design: .rounded)).monospacedDigit()
                    Text("used").font(.system(size: 9)).foregroundStyle(.secondary)
                }
            }
            .frame(width: 48, height: 48)
            HStack(spacing: 3) {
                Text(title).font(.caption.weight(.medium)).lineLimit(2)
                if isMeterWindow {
                    Text("Bar").font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 3)
                        .background(.quaternary, in: Capsule())
                }
            }
            Text(UsageFormatting.countdown(to: window.resetsAt).replacingOccurrences(of: "Resets in ", with: "Reset "))
                .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 5)
        .padding(.vertical, 4)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(window.name)\(isMeterWindow ? ", shown in menu bar" : "")")
        .accessibilityValue("\(UsageFormatting.percent(window.clampedUsedPercent)) used, \(UsageFormatting.percent(window.remainingPercent)) remaining. \(UsageFormatting.countdown(to: window.resetsAt))")
        .help(window.name)
    }

    private var title: String {
        switch window.name {
        case "5-hour session": "5 hours"
        case "Weekly": "7 days"
        default: window.name
        }
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
                    if let snapshot = state.snapshot {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Measured \(snapshot.fetchedAt.formatted(date: .abbreviated, time: .standard))")
                            Text(snapshot.source ?? "Legacy cached measurement")
                            Text(snapshot.account ?? "Account identity not supplied by this source")
                            if state.hasStaleData() {
                                Text("Last known data — current quota is unconfirmed").foregroundStyle(.orange)
                            }
                        }.font(.caption).foregroundStyle(.secondary)
                        ForEach(snapshot.windows) { window in
                            UsageWindowDetailRow(window: window, isStale: state.hasStaleData(), isMeterWindow: window.id == snapshot.meterWindow?.id, samples: history.series(for: snapshot, window: window))
                            Divider()
                        }
                    } else {
                        Text("No usage data yet.").foregroundStyle(.secondary)
                    }
                    if let error = state.errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption).foregroundStyle(.orange)
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
