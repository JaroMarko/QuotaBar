import QuotaBarCore
import SwiftUI

@main
struct QuotaBarApp: App {
    @StateObject private var store = UsageStore.shared

    var body: some Scene {
        MenuBarExtra {
            QuotaBarMenuView(store: store)
        } label: {
            MenuBarLabel(store: store)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(preferences: store.preferences)
        }
    }
}
