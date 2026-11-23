import Foundation
import QuotaBarCore
import ServiceManagement

enum MenuBarMode: String, CaseIterable, Identifiable {
    case concentric, columns, semicircles, claude, codex, gemini, iconOnly
    var id: String { rawValue }
    var title: String {
        switch self {
        case .concentric: "Tri prstence"
        case .columns: "Zvislé stĺpce"
        case .semicircles: "Polkruhy · Claude a Codex"
        case .claude: "Iba Claude"
        case .codex: "Iba Codex"
        case .gemini: "Iba Gemini"
        case .iconOnly: "Iba ikona QuotaBar"
        }
    }
    var hasCenterMark: Bool { self == .concentric || self == .semicircles }

    var providers: [ProviderKind] {
        switch self {
        case .claude: [.claude]
        case .codex: [.codex]
        case .gemini: [.gemini]
        case .concentric, .columns: [.claude, .codex, .gemini]
        case .semicircles: [.claude, .codex]
        case .iconOnly: []
        }
    }
    var explanation: String {
        switch self {
        case .concentric: "Prstence ukazujú využitie od vonkajšieho po vnútorný: Claude 5 h, Codex 7 dní, Gemini 5 h."
        case .columns: "Zľava Claude 5 h, Codex 7 dní a Gemini 5 h. Farebná časť rastie zhora nadol podľa vyčerpanej kvóty."
        case .claude: "Využitie päťhodinového okna Claude."
        case .codex: "Využitie týždenného okna Codexu."
        case .gemini: "Využitie päťhodinového okna Gemini."
        case .iconOnly: "Kliknutím na ikonu otvoríš prehľad kvót."
        case .semicircles: "Vľavo využitie päťhodinového okna Claude, vpravo týždenného okna Codexu."
        }
    }
}

@MainActor
final class AppPreferences: ObservableObject {
    private enum Key {
        static let showsCenterMark = "showsCenterMark"
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

    @Published var showsCenterMark: Bool {
        didSet { defaults.set(showsCenterMark, forKey: Key.showsCenterMark) }
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
        showsCenterMark = defaults.object(forKey: Key.showsCenterMark) as? Bool ?? true
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
