import FoundationModels
import Foundation

/// Sprachmodell-Anbindung an das systemeigene Modell von macOS 26.
/// Alles läuft lokal auf dem Gerät – es verlassen keine Daten den Mac,
/// und es wird kein Schlüssel und kein Konto benötigt.
@available(macOS 26, *)
@MainActor
final class OnDeviceBackend: AssistantBackend {

    private let makeContext: () -> AssistantContext
    private var session: LanguageModelSession?
    private var context: AssistantContext?

    init(context: @escaping () -> AssistantContext) {
        self.makeContext = context
    }

    var unavailable: AssistantUnavailable? {
        switch SystemLanguageModel.default.availability {
        case .available:
            return nil
        case .unavailable(.appleIntelligenceNotEnabled):
            return .appleIntelligenceOff
        case .unavailable(.deviceNotEligible):
            return .notEligible
        case .unavailable(.modelNotReady):
            return .modelNotReady
        case .unavailable(let reason):
            return .other("Das lokale Sprachmodell steht nicht zur Verfügung (\(reason)).")
        @unknown default:
            return .other("Das lokale Sprachmodell steht nicht zur Verfügung.")
        }
    }

    func reset() {
        session = nil
        context = nil
    }

    /// Beantwortet die Frage. Läuft das Kontextfenster über – das ist bei einem
    /// On-Device-Modell schnell erreicht –, wird die Sitzung verworfen und die
    /// Frage einmal neu gestellt, statt den Benutzer abzuweisen.
    /// Rückgabe: ob dabei der Gesprächsverlauf zurückgesetzt wurde.
    @discardableResult
    func respond(to prompt: String, onUpdate: @escaping (String) -> Void) async throws -> Bool {
        do {
            try await stream(prompt, onUpdate: onUpdate)
            return false
        } catch let error as LanguageModelSession.GenerationError {
            guard case .exceededContextWindowSize = error else { throw error }
            session = nil
            onUpdate("")
            try await stream(prompt, onUpdate: onUpdate)
            return true
        } catch {
            // Ein misslungener Werkzeugaufruf – etwa wenn das Modell die
            // Argumente fehlerhaft erzeugt hat – ist meist beim zweiten Anlauf
            // erfolgreich. Ohne Verlauf ist der Kontext zudem eindeutiger.
            session = nil
            onUpdate("")
            try await stream(prompt, onUpdate: onUpdate)
            return true
        }
    }

    private func stream(_ prompt: String, onUpdate: @escaping (String) -> Void) async throws {
        let session = try activeSession()
        context?.question = prompt
        for try await snapshot in session.streamResponse(to: prompt) {
            onUpdate(snapshot.content)
        }
    }

    // MARK: - Sitzung

    /// Die Sitzung wird beim ersten Gebrauch erzeugt, damit die Anweisung
    /// den aktuellen Datenstand enthält.
    private func activeSession() throws -> LanguageModelSession {
        if let session { return session }
        let box = makeContext()
        context = box
        let session = LanguageModelSession(
            tools: [
                // lesend
                AppUsageTool(box: box),
                CompareAppsTool(box: box),
                ProductivityTool(box: box),
                CalendarTool(box: box),
                TasksTool(box: box),
                // schreibend
                AddTaskTool(box: box),
                CompleteTaskTool(box: box),
                DeleteTaskTool(box: box),
                AddEventTool(box: box),
                DeleteEventTool(box: box),
                SetCategoryTool(box: box),
                // zeichnend
                ChartTool(box: box)
            ],
            instructions: instructions(box)
        )
        self.session = session
        return session
    }

    private func instructions(_ box: AssistantContext) -> String {
        let query = box.query
        return """
        Du bist die Assistenz eines Mac-Dashboards: App-Nutzung, Produktivität, \
        Termine und Aufgaben. Du gibst Auskunft, legst Einträge an, änderst und \
        löschst sie und zeichnest Diagramme und Tabellen.

        \(query.snapshot())\(box.lastChartNote.isEmpty ? "" : "\nZuletzt gezeigt: \(box.lastChartNote).")

        Regeln:
        - Jede Auskunft und jede Änderung läuft über ein Werkzeug. Behaupte nie \
        etwas, das kein Werkzeug bestätigt hat.
        - Fehlt eine Angabe, nimm den Standard und frage nicht nach. Handle sofort.
        - Gib die Rückmeldung des Werkzeugs sinngemäß wieder, mit genau den \
        Anwendungen daraus.
        - Rechne nicht selbst. Ohne Zeitangabe nimm 7 Tage.
        - Für Diagramme und Tabellen: diagramm_zeichnen mit form (kuchen, balken, \
        saeulen, linie, tabelle) und inhalt (apps, einstufung, score, aufgaben, \
        termine). Schreibe keine Tabelle in den Text.

        Antworte auf Deutsch, sachlich, zwei bis drei Sätze. Duze den Benutzer.
        """
    }
}
