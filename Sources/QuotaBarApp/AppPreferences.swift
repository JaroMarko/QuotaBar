import Foundation
import QuotaBarCore
import ServiceManagement

@MainActor
final class AppPreferences: ObservableObject {
    private enum Key {
        static let launchAtLogin = "launchAtLogin"
        static let notification75 = "notification75"
        static let notification90 = "notification90"
        static let notification100 = "notification100"
        static let notificationReset = "notificationReset"
        static let defaultsRegistered = "defaultsRegistered"
    }

    @Published var launchAtLogin: Bool {
        didSet {
            defaults.set(launchAtLogin, forKey: Key.launchAtLogin)
            updateLaunchAtLogin()
        }
    }
    @Published var notification75: Bool { didSet { defaults.set(notification75, forKey: Key.notification75) } }
    @Published var notification90: Bool { didSet { defaults.set(notification90, forKey: Key.notification90) } }
    @Published var notification100: Bool { didSet { defaults.set(notification100, forKey: Key.notification100) } }
    @Published var notificationReset: Bool { didSet { defaults.set(notificationReset, forKey: Key.notificationReset) } }
    @Published private(set) var launchAtLoginError: String?

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if !defaults.bool(forKey: Key.defaultsRegistered) {
            defaults.set(true, forKey: Key.launchAtLogin)
            defaults.set(true, forKey: Key.notification75)
            defaults.set(true, forKey: Key.notification90)
            defaults.set(true, forKey: Key.notification100)
            defaults.set(true, forKey: Key.notificationReset)
            defaults.set(true, forKey: Key.defaultsRegistered)
        }
        launchAtLogin = defaults.bool(forKey: Key.launchAtLogin)
        notification75 = defaults.bool(forKey: Key.notification75)
        notification90 = defaults.bool(forKey: Key.notification90)
        notification100 = defaults.bool(forKey: Key.notification100)
        notificationReset = defaults.bool(forKey: Key.notificationReset)
    }

    var enabledThresholds: [Int] {
        var values: [Int] = []
        if notification75 { values.append(75) }
        if notification90 { values.append(90) }
        if notification100 { values.append(100) }
        return values
    }

    func applyInitialLaunchAtLoginPreference() {
        guard launchAtLogin else { return }
        updateLaunchAtLogin()
    }

    private func updateLaunchAtLogin() {
        do {
            if launchAtLogin {
                if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
            } else if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = "Launch at login could not be updated."
        }
    }
}
