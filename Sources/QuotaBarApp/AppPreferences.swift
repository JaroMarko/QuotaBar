import Foundation
import QuotaBarCore
import ServiceManagement

enum MenuBarMode: String, CaseIterable, Identifiable {
    case concentric, claude, codex, iconOnly, semicircles
    var id: String { rawValue }
    var title: String {
        switch self {
        case .concentric: "Both — concentric rings"
        case .claude: "Claude only"
        case .codex: "Codex only"
        case .iconOnly: "QuotaBar icon only"
        case .semicircles: "Both — semicircles"
        }
    }
    var providers: [ProviderKind] {
        switch self {
        case .claude: [.claude]
        case .codex: [.codex]
        case .concentric, .semicircles: [.claude, .codex]
        case .iconOnly: []
        }
    }
    var explanation: String {
        switch self {
        case .concentric: "Used quota: outer terracotta ring Claude 5h; inner cyan ring Codex most-used window."
        case .claude: "Menu bar shows used quota: Claude 5-hour session."
        case .codex: "Menu bar shows used quota: Codex most-used window."
        case .iconOnly: "Menu bar shows the QuotaBar icon; quota details are shown in this popup."
        case .semicircles: "Used quota: left terracotta half Claude 5h; right cyan half Codex most-used window."
        }
    }
}

@MainActor
final class AppPreferences: ObservableObject {
    private enum Key {
        static let menuBarMode = "menuBarMode"
        static let launchAtLogin = "launchAtLogin"
        static let notification75 = "notification75"
        static let notification90 = "notification90"
        static let notification100 = "notification100"
        static let notificationReset = "notificationReset"
        static let defaultsRegistered = "defaultsRegistered"
    }

    @Published var menuBarMode: MenuBarMode {
        didSet { defaults.set(menuBarMode.rawValue, forKey: Key.menuBarMode) }
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
        menuBarMode = defaults.string(forKey: Key.menuBarMode).flatMap(MenuBarMode.init(rawValue:)) ?? .concentric
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
