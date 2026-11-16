import SwiftUI

/// Beschreibung eines Diagramms, das die Assistenz erzeugt hat.
///
/// Bewusst als reine Datenstruktur: das Sprachmodell wählt nur Art, Zeitraum
/// und Anwendungen – die Werte kommen aus den Aufzeichnungen, gezeichnet wird
/// mit Swift Charts. Damit kann das Modell keine Zahlen erfinden.
struct ChartSpec: Identifiable, Equatable {
    enum Style: Equatable {
        /// Gruppierte Säulen – Vergleich mehrerer Reihen über eine Achse.
        case groupedBars
        /// Waagerechte Balken – Rangliste.
        case horizontalBars
        /// Linie – Verlauf einer einzelnen Reihe.
        case line
        /// Ring – Anteile eines Ganzen.
        case donut
        /// Tabelle – wenn es auf einzelne Einträge ankommt statt auf Größen.
        case table
    }

    /// Inhalt einer Tabelle. Nur gesetzt, wenn `style == .table`.
    struct Table: Equatable {
        let columns: [String]
        let rows: [[String]]
    }

    let id = UUID()
    let title: String
    let subtitle: String
    let style: Style
    /// Beschriftung der Werteachse, etwa „Minuten“.
    let unit: String
    let series: [ChartSeries]
    var table: Table?

    /// Enthält die Darstellung überhaupt etwas?
    var hasData: Bool {
        if style == .table { return !(table?.rows.isEmpty ?? true) }
        return series.contains { $0.points.contains { $0.value > 0 } }
    }

    static func == (a: ChartSpec, b: ChartSpec) -> Bool { a.id == b.id }
}

struct ChartSeries: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let color: Color
    let points: [ChartPoint]

    var total: Double { points.reduce(0) { $0 + $1.value } }

    static func == (a: ChartSeries, b: ChartSeries) -> Bool { a.id == b.id }
}

struct ChartPoint: Identifiable, Equatable {
    let id = UUID()
    /// Beschriftung auf der Kategorieachse, etwa „15:00“ oder „Mi 9.9.“.
    let label: String
    let value: Double
    /// Nur für Ring- und Balkendiagramme, bei denen jeder Punkt eine
    /// eigene Farbe trägt statt der Farbe seiner Reihe.
    var color: Color?

    static func == (a: ChartPoint, b: ChartPoint) -> Bool { a.id == b.id }
}

/// Sammelt die Diagramme eines Gesprächszugs – analog zum `ActionLog`.
@MainActor
final class ChartLog {
    private(set) var charts: [ChartSpec] = []

    /// Was zuletzt gezeichnet wurde – geht in die Systemanweisung ein, damit
    /// Anschlussfragen („nimm die anderen dazu“) auch nach dem Leeren des
    /// Verlaufs noch einen Bezug haben.
    private(set) var lastSummary: String?

    func record(_ spec: ChartSpec) {
        charts.append(spec)
        lastSummary = "\(spec.title) – \(spec.subtitle)"
    }

    func drain() -> [ChartSpec] {
        defer { charts.removeAll() }
        return charts
    }
}
