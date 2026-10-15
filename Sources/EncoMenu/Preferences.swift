import AppKit
import Combine

enum EarbudFinish: String, CaseIterable, Identifiable {
    case pearlWhite, matteBlack
    var id: String { rawValue }
    var title: String { self == .pearlWhite ? "Pearl White" : "Matte Black" }
    var color: NSColor { self == .pearlWhite ? NSColor(white: 0.91, alpha: 1) : NSColor(white: 0.085, alpha: 1) }
}

enum MenuBarIcon: String, CaseIterable, Identifiable {
    case earbuds, chargingCase
    var id: String { rawValue }
    var title: String { self == .earbuds ? "Earbuds" : "Charging case" }
}

final class Preferences: ObservableObject {
    @Published var finish: EarbudFinish {
        didSet { UserDefaults.standard.set(finish.rawValue, forKey: "earbudFinish") }
    }
    @Published var menuIcon: MenuBarIcon {
        didSet { UserDefaults.standard.set(menuIcon.rawValue, forKey: "menuIcon") }
    }
    @Published var hasChosenFinish: Bool {
        didSet { UserDefaults.standard.set(hasChosenFinish, forKey: "hasChosenFinish") }
    }

    init() {
        finish = EarbudFinish(rawValue: UserDefaults.standard.string(forKey: "earbudFinish") ?? "") ?? .pearlWhite
        menuIcon = MenuBarIcon(rawValue: UserDefaults.standard.string(forKey: "menuIcon") ?? "") ?? .earbuds
        hasChosenFinish = UserDefaults.standard.bool(forKey: "hasChosenFinish")
    }
}
