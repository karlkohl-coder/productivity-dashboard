import SwiftUI

/// Einstufung einer Anwendung.
enum ProductivityCategory: String, Codable, CaseIterable, Identifiable {
    case productive
    case neutral
    case unproductive

    var id: String { rawValue }

    var label: String {
        switch self {
        case .productive:   return "Produktiv"
        case .neutral:      return "Neutral"
        case .unproductive: return "Unproduktiv"
        }
    }

    var color: Color {
        switch self {
        case .productive:   return Theme.Palette.productive
        case .neutral:      return Theme.Palette.neutral
        case .unproductive: return Theme.Palette.unproductive
        }
    }

    var symbol: String {
        switch self {
        case .productive:   return "arrow.up.right"
        case .neutral:      return "minus"
        case .unproductive: return "arrow.down.right"
        }
    }

    /// Gewicht für den Produktivitäts-Score (0…100).
    var score: Double {
        switch self {
        case .productive:   return 1
        case .neutral:      return 0.5
        case .unproductive: return 0
        }
    }
}

/// Ein zusammenhängender Zeitraum, in dem eine App im Vordergrund war.
struct ActivitySegment: Codable, Identifiable, Hashable {
    var id = UUID()
    var bundleID: String
    var appName: String
    var start: Date
    var end: Date

    var duration: TimeInterval { max(0, end.timeIntervalSince(start)) }
}

/// Aggregat pro App für einen Zeitraum – Basis für Listen und Diagramme.
struct AppUsage: Identifiable, Hashable {
    var id: String { bundleID }
    let bundleID: String
    let appName: String
    let seconds: TimeInterval
    let category: ProductivityCategory
}
