import AppKit
import QuotaBarCore
import SwiftUI

final class QuotaBarDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // MenuBarExtra labels are rendered as images: their view task is not
        // an application lifecycle callback. Start monitoring exactly once here.
        UsageStore.shared.start()
    }
}

@main
struct QuotaBarApp: App {
    @NSApplicationDelegateAdaptor(QuotaBarDelegate.self) private var delegate
    @StateObject private var store = UsageStore.shared

    var body: some Scene {
        MenuBarExtra {
            QuotaBarMenuView(store: store)
        } label: {
            MenuBarLabel(store: store)
        }
        .menuBarExtraStyle(.window)
        Settings { SettingsView(preferences: store.preferences) }
    }
}
