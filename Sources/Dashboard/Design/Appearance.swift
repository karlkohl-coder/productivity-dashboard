import SwiftUI

/// Erscheinungsbild der App. „System“ folgt der Einstellung von macOS.
enum AppearanceMode: String, CaseIterable, Identifiable, Codable {
    case system, light, dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "System"
        case .light:  return "Hell"
        case .dark:   return "Dunkel"
        }
    }

    var symbol: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light:  return "sun.max"
        case .dark:   return "moon"
        }
    }

    /// nil bedeutet: der Systemeinstellung folgen.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}

@MainActor
final class AppearanceSettings: ObservableObject {
    private static let key = "appearance.mode"

    @Published var mode: AppearanceMode {
        didSet {
            UserDefaults.standard.set(mode.rawValue, forKey: Self.key)
            apply()
        }
    }

    init() {
        let stored = UserDefaults.standard.string(forKey: Self.key) ?? ""
        mode = AppearanceMode(rawValue: stored) ?? .system
        apply()
    }

    /// Setzt zusätzlich das Erscheinungsbild der ganzen App. Ohne das behielten
    /// Menüs, Einstellungsfenster und Systemsteuerelemente das Aussehen des
    /// Systems bei, während der Fensterinhalt schon umgeschaltet hätte.
    private func apply() {
        switch mode {
        case .system: NSApp?.appearance = nil
        case .light:  NSApp?.appearance = NSAppearance(named: .aqua)
        case .dark:   NSApp?.appearance = NSAppearance(named: .darkAqua)
        }
    }

    func cycle() {
        let all = AppearanceMode.allCases
        let next = (all.firstIndex(of: mode).map { $0 + 1 } ?? 0) % all.count
        mode = all[next]
    }
}
