import AppKit
import QuotaBarCore
import SwiftUI

struct MenuBarLabel: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "chart.bar.fill")
            Text(store.menuBarText)
                .monospacedDigit()
        }
        .accessibilityLabel("Plan usage \(store.menuBarText)")
        .task { store.start() }
    }
}

struct QuotaBarMenuView: View {
    @ObservedObject var store: UsageStore
    @State private var showingAbout = false

    var body: some View {
        VStack(spacing: 12) {
            header
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(store.orderedStates) { state in
                        ProviderCard(state: state)
                    }
                }
            }
            .frame(maxHeight: 470)
            footer
        }
        .padding(14)
        .frame(width: 370)
        .task { await store.refreshIfStale() }
        .sheet(isPresented: $showingAbout) { AboutView() }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("QuotaBar")
                    .font(.headline)
                Text(lastUpdatedText)
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
            SettingsLink {
                Label("Settings", systemImage: "gearshape")
            }
            .buttonStyle(.borderless)
            Button("About") { showingAbout = true }
                .buttonStyle(.borderless)
            Spacer()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.borderless)
        }
        .font(.caption)
    }

    private var lastUpdatedText: String {
        guard let date = store.lastRefreshAt else { return "Waiting for first refresh" }
        return "Updated \(date.formatted(date: .omitted, time: .shortened))"
    }
}

struct ProviderCard: View {
    let state: ProviderDisplayState

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
                if state.isStale {
                    Image(systemName: "clock.badge.exclamationmark")
                        .foregroundStyle(.secondary)
                        .help("Showing last known usage")
                }
            }

            if let snapshot = state.snapshot {
                ForEach(snapshot.windows) { window in
                    UsageWindowRow(window: window)
                    if window.id != snapshot.windows.last?.id {
                        Divider().opacity(0.55)
                    }
                }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(window.name)
                    .font(.subheadline.weight(.medium))
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
        }
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
                Text("Usage refreshes every five minutes, on wake, and when the menu opens.")
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
            Text("Version 1.0.0")
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
