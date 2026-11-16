import Foundation

/// Liest aus der Frage des Benutzers heraus, was gezeichnet werden soll.
///
/// Das Sprachmodell liefert zwar Argumente, legt sie sich aber gelegentlich
/// selbst zurecht. Form, Inhalt, Zeitraum und Anzahl stehen jedoch fast
/// immer wörtlich in der Frage – wer sie dort ausliest, ist nicht auf das
/// Modell angewiesen. Dessen Angaben füllen nur, was die Frage offenlässt.
struct ChartRequest {

    /// Was abgebildet wird.
    enum Subject {
        case apps          // Anwendungen und ihre Zeiten
        case categories    // produktiv / neutral / unproduktiv
        case score         // Produktivitäts-Score
        case tasks         // Aufgaben
        case events        // Kalendertermine
    }

    /// Wie es abgebildet wird.
    enum Shape {
        case unspecified
        case pie           // Kuchen / Ring
        case bars          // waagerechte Balken
        case columns       // Säulen über eine Zeitachse
        case line          // Linie
        case table         // Tabelle
    }

    var subject: Subject
    var shape: Shape
    var days: Int
    /// Namentlich genannte Anwendungen, bereits gegen die Daten geprüft.
    var namedApps: [String]
    /// Wie viele Anwendungen gezeigt werden sollen.
    var count: Int
    /// Eine in der Frage ausdrücklich genannte Anzahl („die drei größten“).
    /// Sie sticht alles andere – auch ein zuvor gesetztes „alle“.
    var explicitCount: Int?
    /// „die meistgenutzten“ – dann entscheiden die Daten, nicht das Modell.
    var mostUsed: Bool
    /// „alle“, „die anderen“, „die restlichen“ – jede Anwendung mit Daten.
    var allApps: Bool

    // MARK: - Wortlisten

    /// Wörter, die eine Diagrammform benennen. Sie dienen doppelt: zum
    /// Erkennen der Form und zum Erkennen, dass überhaupt ein Diagramm
    /// gewünscht ist. Eine einzige Liste, damit beides nie auseinanderläuft.
    private static let pieWords     = ["kuchen", "torte", "tortendiagramm", "ring", "pie", "donut", "kreis"]
    private static let tableWords   = ["tabelle", "tabellarisch", "table", "spaltenweise", "auflistung"]
    private static let barWords     = ["balken", "rangliste", "ranking", "liste", "top "]
    private static let columnWords  = ["säulen", "saeulen", "spalten"]
    private static let lineWords    = ["linie", "linien", "kurve", "verlaufskurve"]
    private static let genericWords = ["diagramm", "grafik", "grafisch", "graph", "chart",
                                       "zeichne", "visuell", "visualisier", "veranschaulich",
                                       "plot", "schaubild", "abbildung", "darstellung",
                                       "bildlich", "gegenüberstellung", "gegenueberstellung",
                                       "gegenüberstellen", "stundenweise", "tageweise"]

    /// Nennt die Frage den Inhalt ausdrücklich? Nur dann darf sie die Wahl
    /// des Modells überstimmen – sonst bleibt dem Modell die Freiheit.
    static func explicitSubject(_ question: String, availableApps: [String]) -> Subject? {
        let t = question.lowercased()
        if ["aufgabe", "aufgaben", "todo", "to-do", "to do", "erledigen", "zu erfüllen",
            "zu erledigen", "checkliste"].contains(where: { t.contains($0) }) { return .tasks }
        if ["termin", "kalender", "meeting", "besprechung", "verabredung"]
            .contains(where: { t.contains($0) }) { return .events }
        if ["score", "punkte", "punktzahl"].contains(where: { t.contains($0) }) { return .score }
        if ["einstufung", "produktiv", "unproduktiv", "neutral", "kategorie"]
            .contains(where: { t.contains($0) }) { return .categories }
        if ["app", "anwendung", "programm"].contains(where: { t.contains($0) }) { return .apps }
        if availableApps.contains(where: { matches($0, in: t) }) { return .apps }
        return nil
    }

    /// Nennt die Frage die Form ausdrücklich?
    static func explicitShape(_ question: String) -> Shape? {
        let shape = parseShape(effective(question.lowercased()))
        return shape == .unspecified ? nil : shape
    }

    /// Schneidet ab, was nach einer Verneinung steht. „Als Balkendiagramm
    /// statt Linie“ nennt zwei Formen; gemeint ist nur die erste.
    private static func effective(_ text: String) -> String {
        for marker in [" statt ", " anstatt ", " anstelle ", " nicht als ", " und nicht "] {
            if let range = text.range(of: marker) {
                return String(text[text.startIndex..<range.lowerBound])
            }
        }
        return text
    }

    /// Lässt sich aus der Frage überhaupt ein Inhalt ableiten? Nur dann darf
    /// die App von sich aus zeichnen. Sonst käme für „zeichne mir X“ mit
    /// unbekanntem X ein beliebiges Anwendungsdiagramm heraus – genau das
    /// ist einmal passiert, als „Tabelle mit allen Aufgaben“ als Diagramm
    /// der App-Nutzung endete.
    static func hasKnownSubject(_ question: String, availableApps: [String]) -> Bool {
        if explicitSubject(question, availableApps: availableApps) != nil { return true }
        let t = question.lowercased()
        return ["genutzt", "benutzt", "nutzung", "verwendet", "zeit", "produktivität",
                "verteilung", "rangliste"].contains { t.contains($0) }
    }

    /// Verändert die Frage ein eben gezeigtes Diagramm, ohne selbst eines
    /// zu benennen? „Zeig nur die drei größten davon“ ist eine
    /// Diagrammanfrage – aber nur, wenn gerade eines zu sehen war.
    static func isRefinement(_ question: String) -> Bool {
        let t = effective(question.lowercased())
        if mentionsSelection(t) { return true }
        if parseShape(t) != .unspecified { return true }
        return ["davon", "dazu", "stattdessen", "größten", "groessten", "kleinsten",
                "restlichen", "übrigen", "uebrigen", "anderen"].contains { t.contains($0) }
    }

    /// Ist überhaupt ein Diagramm gewünscht?
    static func isChartRequest(_ question: String) -> Bool {
        let t = question.lowercased()
        return (pieWords + tableWords + barWords + columnWords + lineWords + genericWords)
            .contains { t.contains($0) }
    }

    // MARK: - Auswertung

    /// Ist in der Frage überhaupt eine Anzahl oder eine Auswahl genannt?
    /// Nur dann darf die Auswertung der Frage die Wahl des Modells überstimmen.
    static func mentionsSelection(_ question: String) -> Bool {
        let t = question.lowercased()
        return ["alle", "sämtliche", "die anderen", "anderen anwendungen", "restlichen",
                "übrigen", "beiden", "beide", "zwei", "drei", "vier", "fünf", "top "]
            .contains { t.contains($0) }
    }

    static func mentionsShape(_ question: String) -> Bool {
        parse(question: question, availableApps: []).shape != .unspecified
    }

    static func parse(question: String, availableApps: [String]) -> ChartRequest {
        let text = effective(question.lowercased())

        let shape = parseShape(text)
        let subject = parseSubject(text, shape: shape)
        let named = availableApps.filter { matches($0, in: text) }
        let mostUsed = ["meistgenutzt", "meist genutzt", "am meisten", "am häufigsten",
                        "häufigsten", "meiste zeit", "top "].contains { text.contains($0) }

        let all = ["alle", "sämtliche", "saemtliche", "die anderen", "anderen anwendungen",
                   "restlichen", "übrigen", "uebrigen", "jede app", "jede anwendung",
                   "komplett", "insgesamt alle"].contains { text.contains($0) }

        return ChartRequest(
            subject: subject,
            shape: shape,
            days: parseDays(text),
            namedApps: mostUsed ? [] : named,
            count: parseCount(text, named: named.count, shape: shape),
            explicitCount: parseExplicitCount(text),
            mostUsed: mostUsed || named.isEmpty,
            allApps: all
        )
    }

    /// Trifft der Name der Anwendung in der Frage? Neben dem vollen Namen
    /// zählt auch ein kennzeichnendes Wort daraus – „Chrome“ meint „Google
    /// Chrome“, „Einstellungen“ meint „Systemeinstellungen“.
    private static func matches(_ appName: String, in text: String) -> Bool {
        let name = appName.lowercased()
        if text.contains(name) { return true }
        return name
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 5 }
            .contains { text.contains($0) }
    }

    private static func parseShape(_ text: String) -> Shape {
        if tableWords.contains(where: { text.contains($0) }) { return .table }
        if pieWords.contains(where: { text.contains($0) }) { return .pie }
        if columnWords.contains(where: { text.contains($0) }) { return .columns }
        if lineWords.contains(where: { text.contains($0) }) { return .line }
        // „Balken“, aber auch „Rangliste“ und „Top 5“ – dort ist die Liste
        // gemeint. „Die beiden meistgenutzten“ bleibt bewusst außen vor,
        // das ist eine Gegenüberstellung.
        if barWords.contains(where: { text.contains($0) }) { return .bars }
        return .unspecified
    }

    /// Wichtig: „Kuchendiagramm“ sagt etwas über die Form, nicht über den
    /// Inhalt. Nur ausdrückliche Begriffe zur Einstufung oder zum Score
    /// verschieben das Thema weg von den Anwendungen.
    private static func parseSubject(_ text: String, shape: Shape) -> Subject {
        if ["aufgabe", "todo", "to-do", "zu erfüllen", "zu erledigen"]
            .contains(where: { text.contains($0) }) { return .tasks }
        if ["termin", "kalender", "meeting"].contains(where: { text.contains($0) }) { return .events }
        if ["score", "punkte", "punktzahl"].contains(where: { text.contains($0) }) { return .score }
        if ["produktiv", "unproduktiv", "neutral", "einstufung", "kategorie"]
            .contains(where: { text.contains($0) }) { return .categories }
        return .apps
    }

    private static func parseDays(_ text: String) -> Int {
        if text.contains("heute") || text.contains("heutigen") { return 1 }
        if text.contains("gestern") { return 2 }
        if text.contains("quartal") { return 90 }
        if text.contains("monat") { return 30 }
        if text.contains("woche") { return 7 }
        // „letzten 14 Tage“ – die Zahl muss neben dem Wort Tag stehen.
        if let range = text.range(of: #"(\d+)\s*tag"#, options: .regularExpression),
           let number = Int(text[range].filter(\.isNumber)), (1...90).contains(number) {
            return number
        }
        return 7
    }

    /// „die beiden“, „drei Apps“, „top 5“. Reine Zahlen ohne Bezug werden
    /// bewusst ignoriert – „letzten 7 Tage“ meint keine sieben Anwendungen.
    /// Nur eine wirklich genannte Anzahl, sonst nil.
    private static func parseExplicitCount(_ text: String) -> Int? {
        let words: [(String, Int)] = [
            ("beiden", 2), ("beide", 2), ("zwei", 2), ("drei", 3),
            ("vier", 4), ("fünf", 5), ("fuenf", 5), ("sechs", 6)
        ]
        if let hit = words.first(where: { text.contains($0.0) }) { return hit.1 }
        if let range = text.range(of: #"top\s*(\d+)"#, options: .regularExpression),
           let number = Int(text[range].filter(\.isNumber)), (1...12).contains(number) {
            return number
        }
        return nil
    }

    private static func parseCount(_ text: String, named: Int, shape: Shape) -> Int {
        if let explicit = parseExplicitCount(text) { return explicit }
        // Nennt die Frage Anwendungen, sind genau die gemeint – „nur Chrome“
        // darf keine zweite dazubekommen.
        if named >= 1 { return named }
        // Ohne Angabe: Ranglisten zeigen mehr, Gegenüberstellungen zwei.
        return shape == .bars ? 8 : 2
    }
}
