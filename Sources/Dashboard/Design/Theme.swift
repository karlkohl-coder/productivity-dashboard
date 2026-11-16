import AppKit
import SwiftUI

/// Zentrale Design-Tokens. Alles Visuelle sollte hierher zeigen,
/// damit sich das Erscheinungsbild an einer Stelle ändern lässt.
enum Theme {

    // MARK: - Farben

    enum Palette {

        /// Farbe, die sich dem Erscheinungsbild anpasst. Nötig, weil die
        /// festen Werte im Dunkelmodus entweder grell wirken oder auf dem
        /// dunklen Grund absaufen.
        static func adaptive(light: (Double, Double, Double),
                             dark: (Double, Double, Double)) -> Color {
            Color(nsColor: NSColor(name: nil) { appearance in
                let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                let c = isDark ? dark : light
                return NSColor(srgbRed: c.0, green: c.1, blue: c.2, alpha: 1)
            })
        }

        static let accent = adaptive(light: (0.29, 0.44, 0.98),
                                     dark:  (0.46, 0.58, 1.00))

        static let productive   = adaptive(light: (0.22, 0.70, 0.47),
                                           dark:  (0.34, 0.80, 0.57))
        static let neutral      = adaptive(light: (0.58, 0.60, 0.65),
                                           dark:  (0.62, 0.65, 0.72))
        static let unproductive = adaptive(light: (0.93, 0.45, 0.35),
                                           dark:  (0.98, 0.55, 0.45))

        /// Farbreihe für Diagramme mit mehreren Datenreihen.
        static let series: [Color] = [
            adaptive(light: (0.29, 0.44, 0.98), dark: (0.46, 0.58, 1.00)),
            adaptive(light: (0.22, 0.70, 0.47), dark: (0.34, 0.80, 0.57)),
            adaptive(light: (0.95, 0.60, 0.20), dark: (0.99, 0.70, 0.32)),
            adaptive(light: (0.70, 0.40, 0.90), dark: (0.78, 0.55, 0.97)),
            adaptive(light: (0.93, 0.45, 0.35), dark: (0.98, 0.55, 0.45)),
            adaptive(light: (0.25, 0.72, 0.78), dark: (0.38, 0.82, 0.88))
        ]

        /// Hintergrund der Inhaltsfläche (leicht abgesetzt von den Karten).
        static let canvas = Color(nsColor: .controlBackgroundColor)
        /// Karten heben sich im Hellen durch Weiß ab, im Dunklen durch eine
        /// Aufhellung – `textBackgroundColor` wäre dort fast schwarz.
        static let card = adaptive(light: (1.00, 1.00, 1.00),
                                   dark:  (0.14, 0.145, 0.155))
        /// Karte unter dem Mauszeiger.
        static let cardHover = adaptive(light: (0.985, 0.988, 1.00),
                                        dark:  (0.18, 0.187, 0.20))
        static let hairline = Color.primary.opacity(0.08)
        static let hairlineStrong = Color.primary.opacity(0.16)

        static let textPrimary = Color.primary
        static let textSecondary = Color.secondary
        static let textTertiary = Color.secondary.opacity(0.65)
    }

    // MARK: - Abstände

    enum Spacing {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 48
    }

    // MARK: - Radien

    enum Radius {
        static let sm: CGFloat = 6
        static let md: CGFloat = 10
        static let lg: CGFloat = 14
    }

    // MARK: - Typografie

    enum Font {
        static let pageTitle = SwiftUI.Font.system(size: 26, weight: .semibold, design: .default)
        static let sectionTitle = SwiftUI.Font.system(size: 13, weight: .semibold)
        static let metric = SwiftUI.Font.system(size: 30, weight: .medium, design: .rounded)
        static let body = SwiftUI.Font.system(size: 13)
        static let caption = SwiftUI.Font.system(size: 11)
        static let mono = SwiftUI.Font.system(size: 12, design: .monospaced)
    }
}
