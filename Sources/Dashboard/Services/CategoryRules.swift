import AppKit
import Foundation

/// Die von macOS vergebenen App-Kategorien (`LSApplicationCategoryType`)
/// und ihre Übersetzung in eine Produktivitäts-Einstufung.
enum AppCategoryCatalog {
    static let mapping: [String: ProductivityCategory] = [
        "public.app-category.developer-tools":     .productive,
        "public.app-category.productivity":        .productive,
        "public.app-category.business":            .productive,
        "public.app-category.education":           .productive,
        "public.app-category.graphics-design":     .productive,
        "public.app-category.reference":           .productive,
        "public.app-category.finance":             .productive,
        "public.app-category.medical":             .productive,
        "public.app-category.utilities":           .neutral,
        "public.app-category.photography":         .neutral,
        "public.app-category.news":                .neutral,
        "public.app-category.weather":             .neutral,
        "public.app-category.travel":              .neutral,
        "public.app-category.lifestyle":           .neutral,
        "public.app-category.healthcare-fitness":  .neutral,
        "public.app-category.social-networking":   .unproductive,
        "public.app-category.entertainment":       .unproductive,
        "public.app-category.music":               .unproductive,
        "public.app-category.video":               .unproductive,
        "public.app-category.sports":              .unproductive,
        "public.app-category.games":               .unproductive
    ]

    static let labels: [String: String] = [
        "public.app-category.developer-tools":     "Entwickler-Werkzeuge",
        "public.app-category.productivity":        "Produktivität",
        "public.app-category.business":            "Business",
        "public.app-category.education":           "Bildung",
        "public.app-category.graphics-design":     "Grafik & Design",
        "public.app-category.reference":           "Nachschlagewerke",
        "public.app-category.finance":             "Finanzen",
        "public.app-category.medical":             "Medizin",
        "public.app-category.utilities":           "Dienstprogramme",
        "public.app-category.photography":         "Fotografie",
        "public.app-category.news":                "Nachrichten",
        "public.app-category.weather":             "Wetter",
        "public.app-category.travel":              "Reisen",
        "public.app-category.lifestyle":           "Lifestyle",
        "public.app-category.healthcare-fitness":  "Gesundheit & Fitness",
        "public.app-category.social-networking":   "Soziale Netzwerke",
        "public.app-category.entertainment":       "Unterhaltung",
        "public.app-category.music":               "Musik",
        "public.app-category.video":               "Video",
        "public.app-category.sports":              "Sport",
        "public.app-category.games":               "Spiele"
    ]

    static func category(for type: String) -> ProductivityCategory? {
        if let direct = mapping[type] { return direct }
        // Spiele-Unterkategorien, z. B. „public.app-category.action-games“.
        if type.hasSuffix("-games") { return .unproductive }
        return nil
    }
}

/// Wie eine App zu ihrer Einstufung gekommen ist.
enum CategoryAssignment: Hashable {
    /// Vom Dashboard hergeleitet (Startliste oder App-Kategorie des Bundles).
    case automatic(ProductivityCategory, source: AutoSource)
    /// Vom Benutzer festgelegt.
    case manual(ProductivityCategory)

    var category: ProductivityCategory {
        switch self {
        case .automatic(let c, _): return c
        case .manual(let c):       return c
        }
    }

    var isAutomatic: Bool {
        if case .automatic = self { return true }
        return false
    }

    /// Kurzer Hinweis, woher die Einstufung stammt – für Tooltips.
    var explanation: String {
        switch self {
        case .manual:
            return "Von dir festgelegt."
        case .automatic(_, .curated):
            return "Automatisch: aus der mitgelieferten Liste bekannter Anwendungen."
        case .automatic(_, .appCategory(let type)):
            return "Automatisch: die App meldet sich als „\(AutoSource.readableCategory(type))“."
        case .automatic(_, .fallback):
            return "Automatisch: unbekannte App – es gilt die Voreinstellung."
        }
    }
}

enum AutoSource: Hashable {
    case curated
    case appCategory(String)
    case fallback

    /// „public.app-category.developer-tools“ → „Entwickler-Werkzeuge“.
    static func readableCategory(_ raw: String) -> String {
        AppCategoryCatalog.labels[raw] ?? raw
            .replacingOccurrences(of: "public.app-category.", with: "")
            .replacingOccurrences(of: "-", with: " ")
    }
}

/// Auswahlmöglichkeit in den Einstufungs-Menüs.
enum CategoryChoice: Hashable, Identifiable {
    case automatic
    case fixed(ProductivityCategory)

    var id: String {
        switch self {
        case .automatic:      return "auto"
        case .fixed(let c):   return c.rawValue
        }
    }

    var label: String {
        switch self {
        case .automatic:    return "Automatisch"
        case .fixed(let c): return c.label
        }
    }

    static var allCases: [CategoryChoice] {
        [.automatic] + ProductivityCategory.allCases.map(CategoryChoice.fixed)
    }
}

/// Bildet Bundle-IDs auf produktiv / neutral / unproduktiv ab.
///
/// Reihenfolge der Auswertung:
/// 1. manuelle Festlegung des Benutzers
/// 2. mitgelieferte Liste bekannter Anwendungen
/// 3. `LSApplicationCategoryType` aus dem App-Bundle (z. B. „Spiele“)
/// 4. Voreinstellung für Unbekanntes
@MainActor
final class CategoryRules: ObservableObject {

    private static let file = "category-rules.json"

    @Published private(set) var manual: [String: ProductivityCategory] = [:]

    /// Zählt jede Änderung an der Einstufung – siehe `ActivityTracker.revision`.
    private(set) var revision = 0

    /// Kategorie für Apps, die sich auch automatisch nicht einordnen lassen.
    @Published var fallback: ProductivityCategory = .neutral {
        didSet { persist() }
    }

    /// Schaltet die automatische Herleitung über die App-Kategorie ab,
    /// falls jemand ausschließlich mit eigenen Regeln arbeiten möchte.
    @Published var usesAppCategoryHeuristic = true {
        didSet { persist(); objectWillChange.send() }
    }

    /// Ergebnisse der Bundle-Auswertung – die Plattenzugriffe lohnen nur einmal.
    private var appCategoryCache: [String: String?] = [:]

    // MARK: - Startkonfiguration

    private let curated: [String: ProductivityCategory] = [
        // Produktiv
        "com.apple.dt.Xcode":                 .productive,
        "com.microsoft.VSCode":               .productive,
        "com.apple.Terminal":                 .productive,
        "com.googlecode.iterm2":              .productive,
        "com.jetbrains.intellij":             .productive,
        "com.figma.Desktop":                  .productive,
        "com.apple.Notes":                    .productive,
        "notion.id":                          .productive,
        "com.microsoft.Word":                 .productive,
        "com.microsoft.Excel":                .productive,
        "com.apple.iWork.Pages":              .productive,
        "com.apple.iWork.Numbers":            .productive,
        "com.apple.iWork.Keynote":            .productive,
        "com.readdle.PDFExpert-Mac":          .productive,
        "com.apple.Preview":                  .productive,
        "com.anthropic.claudefordesktop":     .productive,
        "com.karlkohl.dashboard":             .productive,

        // Neutral
        "com.apple.mail":                     .neutral,
        "com.apple.iCal":                     .neutral,
        "com.apple.finder":                   .neutral,
        "com.apple.Safari":                   .neutral,
        "com.google.Chrome":                  .neutral,
        "org.mozilla.firefox":                .neutral,
        "com.apple.systempreferences":        .neutral,
        "com.tinyspeck.slackmacgap":          .neutral,
        "us.zoom.xos":                        .neutral,
        "com.apple.MobileSMS":                .neutral,

        // Unproduktiv
        "com.apple.TV":                       .unproductive,
        "com.spotify.client":                 .unproductive,
        "com.netflix.Netflix":                .unproductive,
        "com.valvesoftware.steam":            .unproductive,
        "com.hnc.Discord":                    .unproductive,
        "com.facebook.archon":                .unproductive,
        "ru.keepcoder.Telegram":              .unproductive,
        "net.whatsapp.WhatsApp":              .unproductive,
        "com.apple.AppStore":                 .unproductive
    ]

    // MARK: - Lebenszyklus

    init() {
        if let stored = JSONStore.load(Stored.self, from: Self.file) {
            manual = stored.manual
            fallback = stored.fallback
            usesAppCategoryHeuristic = stored.usesAppCategoryHeuristic ?? true
        }
    }

    // MARK: - Abfragen

    func category(for bundleID: String) -> ProductivityCategory {
        assignment(for: bundleID).category
    }

    func assignment(for bundleID: String) -> CategoryAssignment {
        if let set = manual[bundleID] { return .manual(set) }
        if let known = curated[bundleID] { return .automatic(known, source: .curated) }
        if usesAppCategoryHeuristic,
           let type = appCategoryType(for: bundleID),
           let derived = AppCategoryCatalog.category(for: type) {
            return .automatic(derived, source: .appCategory(type))
        }
        return .automatic(fallback, source: .fallback)
    }

    func choice(for bundleID: String) -> CategoryChoice {
        if let set = manual[bundleID] { return .fixed(set) }
        return .automatic
    }

    /// Liest `LSApplicationCategoryType` aus dem App-Bundle.
    private func appCategoryType(for bundleID: String) -> String? {
        if let cached = appCategoryCache[bundleID] { return cached }
        let value = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            .flatMap { Bundle(url: $0) }
            .flatMap { $0.object(forInfoDictionaryKey: "LSApplicationCategoryType") as? String }
        appCategoryCache[bundleID] = value
        return value
    }

    // MARK: - Änderungen

    func apply(_ choice: CategoryChoice, to bundleID: String) {
        switch choice {
        case .automatic:      manual.removeValue(forKey: bundleID)
        case .fixed(let cat): manual[bundleID] = cat
        }
        persist()
    }

    /// Setzt alle manuellen Zuordnungen zurück auf „Automatisch“.
    func resetAllToAutomatic() {
        manual.removeAll()
        persist()
    }

    var manualCount: Int { manual.count }

    // MARK: - Persistenz

    private func persist() {
        revision &+= 1
        JSONStore.save(Stored(manual: manual,
                              fallback: fallback,
                              usesAppCategoryHeuristic: usesAppCategoryHeuristic),
                       to: Self.file)
    }

    private struct Stored: Codable {
        var manual: [String: ProductivityCategory]
        var fallback: ProductivityCategory
        var usesAppCategoryHeuristic: Bool?
    }
}
