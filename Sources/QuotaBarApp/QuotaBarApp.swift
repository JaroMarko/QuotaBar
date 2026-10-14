import AppKit
import Combine
import QuotaBarCore
import SwiftUI

@MainActor
final class QuotaBarDelegate: NSObject, NSApplicationDelegate {
    static weak var shared: QuotaBarDelegate?
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var settingsWindow: NSWindow?
    private var subscription: AnyCancellable?
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
        let store = UsageStore.shared
        statusItem = NSStatusBar.system.statusItem(withLength: 48)
        statusItem?.button?.target = self
        statusItem?.button?.action = #selector(togglePopover)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: QuotaBarMenuView(store: store))
        updateIcon()
        subscription = store.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async { self?.updateIcon() }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateIcon() }
        }
        store.start()
        if let index = args.firstIndex(of: "--smoke-report"), args.count > index + 1 {
            Task { await SmokeChecks.writeLiveReport(path: args[index + 1]) }
        }
    }

    private func updateIcon() {
        let states = UsageStore.shared.orderedStates
        statusItem?.button?.image = MenuBarIcon.image(states: states)
        statusItem?.button?.toolTip = states.map { state in
            let detail = state.meterValue().map { "\(UsageFormatting.percent($0)) used" } ?? "current usage unavailable"
            return "\(state.provider.displayName): \(detail)"
        }.joined(separator: "\n")
        statusItem?.button?.setAccessibilityLabel("QuotaBar: Claude and Codex quota meters")
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button else { return }
        if popover.isShown { popover.performClose(nil) }
        else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }

    func showSettings() {
        popover.performClose(nil)
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0,y: 0,width: 460,height: 390),
                styleMask: [.titled,.closable], backing: .buffered, defer: false)
            window.title = "QuotaBar Settings"; window.isReleasedWhenClosed = false
            window.contentViewController = NSHostingController(rootView: SettingsView(preferences: UsageStore.shared.preferences))
            window.center(); settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}

@main
@MainActor
enum QuotaBarMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = QuotaBarDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
        withExtendedLifetime(delegate) {}
    }
}
