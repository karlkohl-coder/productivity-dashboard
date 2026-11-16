import FoundationModels
import Foundation

/// Werkzeuge, die das Sprachmodell aufrufen kann. Jedes reicht die Frage an
/// `DashboardQuery` weiter – gerechnet wird dort, das Modell formuliert nur.
///
/// Die Beschreibungen sind bewusst knapp und eindeutig gehalten: das
/// On-Device-Modell wählt zuverlässiger, wenn sich die Werkzeuge klar
/// voneinander abgrenzen.

/// Gemeinsamer Zugriff auf die Daten. Die Werkzeuge laufen außerhalb des
/// Main-Actors, deshalb der ausdrückliche Sprung. Die Werkzeuge selbst
/// setzen macOS 26 voraus – dort steckt das systemeigene Sprachmodell.
@MainActor
final class AssistantContext {
    let query: DashboardQuery
    let commands: DashboardCommands
    let charts: DashboardCharts
    /// Die Frage des aktuellen Zuges. Das Modell reicht Argumente durch, die
    /// es sich zurechtlegt – hier steht, was tatsächlich gefragt wurde.
    var question: String = ""

    /// Fragt der Benutzer nach „den meistgenutzten“, entscheiden die Daten,
    /// nicht die Namen, die das Modell einsetzt.
    var wantsMostUsed: Bool {
        let t = question.lowercased()
        return ["meistgenutzt", "meist genutzt", "am meisten", "am häufigsten",
                "häufigsten", "top ", "meiste zeit"].contains { t.contains($0) }
    }

    /// Kurzbeschreibung des zuletzt gezeigten Diagramms. Steht in der
    /// Systemanweisung, damit Anschlussfragen wie „nimm die anderen dazu“
    /// auch dann noch verständlich sind, wenn der Verlauf geleert wurde.
    var lastChartNote: String { charts.log.lastSummary ?? "" }

    init(query: DashboardQuery, commands: DashboardCommands, charts: DashboardCharts) {
        self.query = query
        self.commands = commands
        self.charts = charts
    }
}

@available(macOS 26, *)
struct AppUsageTool: Tool {
    let name = "nutzung_anzeigen"
    let description = "Wie lange Anwendungen benutzt wurden. Ohne App-Namen die Rangliste, mit App-Namen der Tagesverlauf dieser einen App."
    let box: AssistantContext

    @Generable
    struct Arguments {
        @Guide(description: "Tage rückwirkend, 1 für heute, 7 für diese Woche")
        var tage: Int
        @Guide(description: "Name einer Anwendung, oder leer für die Rangliste aller")
        var app: String
    }

    func call(arguments: Arguments) async throws -> String {
        await MainActor.run {
            let name = arguments.app.trimmingCharacters(in: .whitespaces)
            return name.isEmpty
                ? box.query.appUsage(days: arguments.tage, limit: 8)
                : box.query.singleAppUsage(name, days: arguments.tage)
        }
    }
}

@available(macOS 26, *)
struct CompareAppsTool: Tool {
    let name = "apps_vergleichen"
    let description = "Vergleicht zwei Anwendungen: Gesamtzeit, Durchschnitt, Unterschied, Tagesverlauf."
    let box: AssistantContext

    @Generable
    struct Arguments {
        @Guide(description: "Erste Anwendung. Leer lassen, damit die meistgenutzte gewählt wird.")
        var appEins: String
        @Guide(description: "Zweite Anwendung. Leer lassen, damit die zweitmeistgenutzte gewählt wird.")
        var appZwei: String
        @Guide(description: "Tage rückwirkend")
        var tage: Int
    }

    func call(arguments: Arguments) async throws -> String {
        await MainActor.run {
            box.wantsMostUsed
                ? box.query.compareApps("", "", days: arguments.tage)
                : box.query.compareApps(arguments.appEins, arguments.appZwei, days: arguments.tage)
        }
    }
}

@available(macOS 26, *)
struct ProductivityTool: Tool {
    let name = "produktivitaet_anzeigen"
    let description = "Produktivitätsauswertung: Anteile, Score, bester und schwächster Tag."
    let box: AssistantContext

    @Generable
    struct Arguments {
        @Guide(description: "Tage rückwirkend")
        var tage: Int
    }

    func call(arguments: Arguments) async throws -> String {
        await MainActor.run { box.query.productivitySummary(days: arguments.tage) }
    }
}

@available(macOS 26, *)
struct CalendarTool: Tool {
    let name = "termine_anzeigen"
    let description = "Anstehende Kalendertermine."
    let box: AssistantContext

    @Generable
    struct Arguments {
        @Guide(description: "Tage in die Zukunft, 1 für heute")
        var tage: Int
    }

    func call(arguments: Arguments) async throws -> String {
        await MainActor.run { box.query.upcomingEvents(daysAhead: arguments.tage) }
    }
}

@available(macOS 26, *)
struct TasksTool: Tool {
    let name = "aufgaben_anzeigen"
    let description = "Die Aufgaben im Dashboard."
    let box: AssistantContext

    // Ohne Argumente: ein Bool-Feld hat das Modell hier wiederholt fehlerhaft
    // erzeugt, und die Aufgabenliste ist kurz genug für die volle Ausgabe.
    @Generable
    struct Arguments {}

    func call(arguments: Arguments) async throws -> String {
        await MainActor.run { box.query.taskOverview(includeCompleted: true) }
    }
}

// MARK: - Schreibende Werkzeuge
//
// Ohne diese Werkzeuge behauptet ein Sprachmodell bereitwillig, etwas
// eingetragen zu haben, ohne dass etwas passiert. Jedes Werkzeug meldet
// wörtlich zurück, was tatsächlich geschehen ist, und trägt die Änderung
// ins Protokoll ein, das unter der Antwort angezeigt wird.

@available(macOS 26, *)
struct AddTaskTool: Tool {
    let name = "aufgabe_anlegen"
    let description = "Legt eine neue Aufgabe an."
    let box: AssistantContext

    @Generable
    struct Arguments {
        @Guide(description: "Text der Aufgabe")
        var titel: String
        @Guide(description: "niedrig, normal oder hoch")
        var prioritaet: String
        @Guide(description: "heute, morgen, Wochentag oder 2026-09-15, sonst leer")
        var faellig: String
    }

    func call(arguments: Arguments) async throws -> String {
        await MainActor.run {
            box.commands.addTask(title: arguments.titel,
                                 priority: arguments.prioritaet,
                                 due: arguments.faellig)
        }
    }
}

@available(macOS 26, *)
struct CompleteTaskTool: Tool {
    let name = "aufgabe_abhaken"
    let description = "Hakt eine Aufgabe als erledigt ab."
    let box: AssistantContext

    @Generable
    struct Arguments {
        @Guide(description: "Titel der Aufgabe")
        var titel: String
    }

    func call(arguments: Arguments) async throws -> String {
        await MainActor.run { box.commands.completeTask(title: arguments.titel) }
    }
}

@available(macOS 26, *)
struct DeleteTaskTool: Tool {
    let name = "aufgabe_loeschen"
    let description = "Löscht eine Aufgabe endgültig."
    let box: AssistantContext

    @Generable
    struct Arguments {
        @Guide(description: "Titel der Aufgabe")
        var titel: String
    }

    func call(arguments: Arguments) async throws -> String {
        await MainActor.run { box.commands.deleteTask(title: arguments.titel) }
    }
}

@available(macOS 26, *)
struct AddEventTool: Tool {
    let name = "termin_anlegen"
    let description = "Trägt einen neuen Termin in den Kalender ein."
    let box: AssistantContext

    @Generable
    struct Arguments {
        @Guide(description: "Titel des Termins")
        var titel: String
        @Guide(description: "heute, morgen, Wochentag oder 2026-09-15")
        var datum: String
        @Guide(description: "Uhrzeit wie 14:30, leer lassen für einen ganztägigen Termin")
        var uhrzeit: String
        @Guide(description: "Dauer in Minuten")
        var dauerMinuten: Int
    }

    func call(arguments: Arguments) async throws -> String {
        await MainActor.run {
            // Ganztägig ergibt sich aus der fehlenden Uhrzeit – ein eigenes
            // Bool-Argument hat das Modell nicht zuverlässig erzeugt.
            let time = arguments.uhrzeit.trimmingCharacters(in: .whitespaces)
            return box.commands.addEvent(title: arguments.titel,
                                         date: arguments.datum,
                                         time: time,
                                         durationMinutes: arguments.dauerMinuten,
                                         allDay: time.isEmpty)
        }
    }
}

@available(macOS 26, *)
struct DeleteEventTool: Tool {
    let name = "termin_loeschen"
    let description = "Löscht einen Termin aus dem Kalender."
    let box: AssistantContext

    @Generable
    struct Arguments {
        @Guide(description: "Titel des Termins")
        var titel: String
        @Guide(description: "Tag des Termins, sonst leer")
        var datum: String
    }

    func call(arguments: Arguments) async throws -> String {
        await MainActor.run {
            box.commands.deleteEvent(title: arguments.titel, date: arguments.datum)
        }
    }
}

@available(macOS 26, *)
struct SetCategoryTool: Tool {
    let name = "app_einstufen"
    let description = "Stuft eine Anwendung als produktiv, neutral oder unproduktiv ein."
    let box: AssistantContext

    @Generable
    struct Arguments {
        @Guide(description: "Name der Anwendung")
        var app: String
        @Guide(description: "produktiv, neutral oder unproduktiv")
        var einstufung: String
    }

    func call(arguments: Arguments) async throws -> String {
        await MainActor.run {
            box.commands.setCategory(app: arguments.app, category: arguments.einstufung)
        }
    }
}

// MARK: - Diagramme

/// Ohne dieses Werkzeug tippt das Modell auf Bitten um ein Diagramm eine
/// Markdown-Tabelle – und erfindet die Zahlen darin. Hier wählt es nur Art,
/// Zeitraum und Anwendungen; gezeichnet wird aus den echten Aufzeichnungen.
@available(macOS 26, *)
struct ChartTool: Tool {
    let name = "diagramm_zeichnen"
    let description = "Zeichnet ein Diagramm oder eine Tabelle und zeigt es dem Benutzer an. Für jede Bitte um eine Grafik, ein Diagramm, eine Kurve oder eine Tabelle."
    let box: AssistantContext

    @Generable
    struct Arguments {
        @Guide(description: "Form: kuchen, balken, saeulen, linie oder tabelle")
        var form: String
        @Guide(description: "Inhalt: apps, einstufung, score, aufgaben oder termine")
        var inhalt: String
        @Guide(description: "Tage rückwirkend, 1 für heute")
        var tage: Int
        @Guide(description: "Anwendungen durch Komma getrennt, oder alle für jede benutzte, oder leer für die meistgenutzten")
        var apps: String
        @Guide(description: "Wie viele Anwendungen gezeigt werden, 0 für alle")
        var anzahl: Int
    }

    func call(arguments: Arguments) async throws -> String {
        await MainActor.run {
            box.charts.make(question: box.question,
                            form: arguments.form,
                            content: arguments.inhalt,
                            days: arguments.tage,
                            apps: arguments.apps,
                            count: arguments.anzahl)
        }
    }
}
