import AppKit
import Combine
import QuotaBarCore
import SwiftUI
import UserNotifications

@MainActor
final class QuotaBarDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    static weak var shared: QuotaBarDelegate?
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var menuController: NSHostingController<QuotaBarMenuView>?
    private var settingsWindow: NSWindow?
    private var detailWindows: [ProviderKind: NSWindow] = [:]
    private var subscription: AnyCancellable?
    private var preferencesSubscription: AnyCancellable?
    private var appearanceObservation: NSKeyValueObservation?
    private var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.shared = self
        let args = CommandLine.arguments
        if args.contains("--verify-store") {
            Task { let passed = await SmokeChecks.verifyStore(); exit(passed ? 0 : 1) }
            return
        }
        if let index = args.firstIndex(of: "--preview-icons"), args.count > index + 1 {
            SmokeChecks.writeIconPreview(path: args[index + 1]); NSApplication.shared.terminate(nil); return
        }
        if let index = args.firstIndex(of: "--preview-popup"), args.count > index + 1 {
            Task { let passed = await SmokeChecks.writePopupPreview(path: args[index + 1]); exit(passed ? 0 : 1) }
            return
        }
        if args.contains("--verify-menu") {
            exit(SmokeChecks.verifyMenu() ? 0 : 1)
        }
        UNUserNotificationCenter.current().delegate = self
        let store = UsageStore.shared
        statusItem = NSStatusBar.system.statusItem(withLength: MenuBarIcon.size.width + 4)
        statusItem?.button?.target = self
        statusItem?.button?.action = #selector(handleStatusClick)
        statusItem?.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        popover.behavior = .transient
        let controller = NSHostingController(rootView: QuotaBarMenuView(store: store))
        controller.sizingOptions = [.preferredContentSize]
        menuController = controller
        popover.contentViewController = controller
        updateIcon()
        subscription = store.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async { self?.updateIcon() }
        }
        preferencesSubscription = store.preferences.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async { self?.updateIcon() }
        }
        // Observe the application: status-item snapshots temporarily change the button appearance while drawing.
        appearanceObservation = NSApplication.shared.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in self?.updateIcon() }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateIcon() }
        }
        store.start()
        if let index = args.firstIndex(of: "--smoke-report"), args.count > index + 1 {
            Task { await SmokeChecks.writeLiveReport(path: args[index + 1]) }
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Show quota alerts and previews while Settings/the popover is active.
        completionHandler([.banner, .sound])
    }

    private func updateIcon() {
        let states = UsageStore.shared.orderedStates
        statusItem?.button?.image = MenuBarIcon.image(states: states, mode: UsageStore.shared.preferences.menuBarMode, appearance: statusItem?.button?.effectiveAppearance)
        let mode = UsageStore.shared.preferences.menuBarMode
        statusItem?.button?.toolTip = mode.explanation + "\n" + states.map { state in
            if state.isInactive { return "\(state.provider.displayName): Vypnutá" }
            let detail = state.meterValue().map { "\(state.snapshot?.meterWindow?.name ?? "Quota"): \(UsageFormatting.percent($0)) used" } ?? "current usage unavailable"
            let observed = state.snapshot.map { snapshot in
                state.hasStaleData() ? " · last observed " + DateFormatter.localizedString(from: snapshot.fetchedAt, dateStyle: .short, timeStyle: .short) : ""
            } ?? ""
            return "\(state.provider.displayName): \(detail)\(observed)"
        }.joined(separator: "\n")
        statusItem?.button?.setAccessibilityLabel("QuotaBar. " + UsageStore.shared.preferences.menuBarMode.explanation)
    }

    @objc private func handleStatusClick() {
        if StatusInteraction.isContextClick(NSApplication.shared.currentEvent) {
            guard let button = statusItem?.button else { return }
            popover.performClose(nil)
            StatusInteraction.contextMenu().popUp(positioning: nil,
                at: NSPoint(x: button.bounds.minX, y: button.bounds.minY), in: button)
            return
        }
        togglePopover()
    }

    private func togglePopover() {
        guard let button = statusItem?.button else { return }
        if popover.isShown { popover.performClose(nil) }
        else {
            NSApplication.shared.activate(ignoringOtherApps: true)
            // Resolve the current SwiftUI size before AppKit positions the window.
            // Preferred sizing also tracks cache -> fresh updates while open.
            if let view = menuController?.view {
                view.layoutSubtreeIfNeeded()
                popover.contentSize = view.fittingSize
            }
            popover.show(relativeTo: StatusInteraction.anchor(in: button.bounds),
                         of: button, preferredEdge: .minY)
        }
    }

    func showDetails(for provider: ProviderKind) {
        popover.performClose(nil)
        if detailWindows[provider] == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 560),
                styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            window.minSize = NSSize(width: 410, height: 360)
            window.title = "\(provider.displayName) usage details"
            window.isReleasedWhenClosed = false
            window.contentViewController = NSHostingController(rootView: LiveProviderDetails(store: UsageStore.shared, provider: provider))
            window.center()
            detailWindows[provider] = window
        }
        detailWindows[provider]?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func showSettings() {
        popover.performClose(nil)
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0,y: 0,width: 460,height: 600),
                styleMask: [.titled,.closable], backing: .buffered, defer: false)
            window.title = "QuotaBar Settings"; window.isReleasedWhenClosed = false
            window.contentViewController = NSHostingController(rootView: SettingsView(preferences: UsageStore.shared.preferences))
            window.center(); settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}

@MainActor
enum StatusInteraction {
    static func anchor(in bounds: NSRect) -> NSRect {
        NSRect(x: bounds.midX - 0.5, y: bounds.minY, width: 1, height: bounds.height)
    }

    static func isContextClick(_ event: NSEvent?) -> Bool {
        event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true
    }

    static func contextMenu() -> NSMenu {
        let menu = NSMenu()
        let quit = NSMenuItem(title: "Quit QuotaBar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApplication.shared
        menu.addItem(quit)
        return menu
    }
}

private struct LiveProviderDetails: View {
    @ObservedObject var store: UsageStore
    let provider: ProviderKind

    var body: some View {
        if let state = store.states[provider] {
            ProviderDetailsView(state: state, history: store.history)
        }
    }
}

@main
@MainActor
enum QuotaBarMain {
    static func main() {
        // The mod's writer is a headless command: no GUI, providers, Keychain or network startup.
        if let index = CommandLine.arguments.firstIndex(of: "--capture-claude-usage") {
            guard CommandLine.arguments.count == index + 2,
                  let data = CommandLine.arguments[index + 1].data(using: .utf8) else { exit(1) }
            do { try ClaudeSessionUsageProvider.capture(data: data); exit(0) }
            catch { fputs("Local Claude quota capture failed.\n", stderr); exit(1) }
        }
        let app = NSApplication.shared
        let delegate = QuotaBarDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
        withExtendedLifetime(delegate) {}
    }
}
