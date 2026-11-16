import Foundation
import SwiftUI

/// Eine Nachricht im Gesprächsverlauf.
struct ChatMessage: Identifiable, Equatable {
    enum Role { case user, assistant }

    let id = UUID()
    let role: Role
    var text: String
    var isStreaming = false
    var failed = false
    /// Was die Assistenz während dieser Antwort tatsächlich geändert hat.
    var actions: [AssistantAction] = []
    /// Der Verlauf war voll und wurde vor dieser Antwort geleert.
    var contextWasReset = false
    /// Die Antwort behauptet eine Änderung, die nachweislich nicht stattfand.
    var unverifiedClaim = false
    /// Diagramme, die zu dieser Antwort gezeichnet wurden.
    var charts: [ChartSpec] = []
    /// Richtigstellung, falls der Text andere Anwendungen nennt als das Diagramm.
    var chartCorrection: String?
    /// Das Diagramm hat die App selbst gezeichnet, weil das Modell es nicht tat.
    var chartWasFallback = false
    /// Es wurde eine Darstellung gewünscht, für die es keine gibt.
    var chartUnavailable = false
    let timestamp = Date()

    static func == (a: ChatMessage, b: ChatMessage) -> Bool {
        a.id == b.id && a.text == b.text && a.isStreaming == b.isStreaming
            && a.failed == b.failed && a.actions.count == b.actions.count
            && a.actions.map(\.undone) == b.actions.map(\.undone)
            && a.charts.count == b.charts.count
    }
}

/// Warum die Assistenz nicht zur Verfügung steht.
enum AssistantUnavailable: Equatable {
    case systemTooOld
    case appleIntelligenceOff
    case notEligible
    case modelNotReady
    case other(String)

    var message: String {
        switch self {
        case .systemTooOld:
            return "Die Assistenz braucht macOS 26 oder neuer – dort bringt das System das Sprachmodell mit."
        case .appleIntelligenceOff:
            return "Apple Intelligence ist ausgeschaltet. In den Systemeinstellungen unter „Apple Intelligence & Siri“ lässt es sich aktivieren."
        case .notEligible:
            return "Dieser Mac unterstützt Apple Intelligence nicht, deshalb steht kein lokales Sprachmodell zur Verfügung."
        case .modelNotReady:
            return "Das Sprachmodell wird gerade noch geladen. Das dauert nach dem Einschalten von Apple Intelligence einen Moment."
        case .other(let text):
            return text
        }
    }
}

/// Abstraktion über das Sprachmodell, damit `AssistantEngine` nicht an
/// macOS 26 gebunden ist und später auch ein anderes Modell dahinter
/// stecken könnte.
@MainActor
protocol AssistantBackend: AnyObject {
    var unavailable: AssistantUnavailable? { get }
    func reset()
    /// Beantwortet eine Frage und meldet den Text fortlaufend zurück.
    /// Rückgabe: ob der Gesprächsverlauf dabei zurückgesetzt werden musste.
    @discardableResult
    func respond(to prompt: String, onUpdate: @escaping (String) -> Void) async throws -> Bool
}

/// Steuert das Gespräch: Verlauf, Zustand, Fehlerbehandlung.
@MainActor
final class AssistantEngine: ObservableObject {

    @Published private(set) var messages: [ChatMessage] = []
    @Published private(set) var isResponding = false
    @Published private(set) var unavailable: AssistantUnavailable?

    private var backend: AssistantBackend?
    private let makeBackend: () -> AssistantBackend?
    private let log: ActionLog
    private let chartLog: ChartLog
    private let makeContext: () -> AssistantContext

    init(log: ActionLog, charts: ChartLog, context: @escaping () -> AssistantContext) {
        self.log = log
        self.chartLog = charts
        self.makeContext = context
        self.makeBackend = {
            if #available(macOS 26, *) {
                return OnDeviceBackend(context: context)
            }
            return nil
        }
        let backend = makeBackend()
        self.backend = backend
        // Achtung: nicht zu `backend?.unavailable ?? …` verkürzen – das macht
        // aus „vorhanden und in Ordnung“ dasselbe wie „gar nicht vorhanden“.
        self.unavailable = backend.map(\.unavailable) ?? .systemTooOld
    }

    var isAvailable: Bool { unavailable == nil }

    /// Vorschläge, die als Einstieg angeboten werden.
    let suggestions = [
        "Was steht heute an?",
        "Welche Apps habe ich diese Woche am meisten benutzt?",
        "Wie produktiv war ich in den letzten 7 Tagen?",
        "Zeichne ein Diagramm der beiden heute meistgenutzten Apps",
        "Trage eine Aufgabe ein: Unterlagen vorbereiten, fällig morgen"
    ]

    func send(_ text: String) {
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isResponding, let backend else { return }

        messages.append(ChatMessage(role: .user, text: question))
        let reply = ChatMessage(role: .assistant, text: "", isStreaming: true)
        messages.append(reply)
        let replyID = reply.id
        isResponding = true

        // Protokolle leeren, damit nur dieser Zug gezählt wird.
        _ = log.drain()
        _ = chartLog.drain()

        Task {
            // Der Modellaufruf darf scheitern, ohne den ganzen Zug zu
            // beenden: die Rückfallebene für Diagramme läuft danach
            // trotzdem. Vorher blieb bei einem Fehler auch eine völlig
            // eindeutige Bitte um eine Tabelle unbeantwortet.
            var failure: String?
            do {
                let didReset = try await backend.respond(to: question) { [weak self] partial in
                    self?.update(replyID, text: partial, streaming: true)
                }
                update(replyID, text: nil, streaming: false)
                if didReset { mark(replyID) { $0.contextWasReset = true } }
            } catch {
                failure = Self.describe(error)
                update(replyID, text: "", streaming: false)
            }

            var actions = log.drain()

            // Ein kleines Modell ahmt gelegentlich den Satzbau des vorigen
            // Zuges nach und meldet eine Änderung, ohne das Werkzeug gerufen
            // zu haben. Da nachweislich nichts geschehen ist, kann der
            // Versuch gefahrlos wiederholt werden – ohne Verlauf, damit es
            // kein Vorbild zum Abschreiben gibt.
            if failure == nil, actions.isEmpty, Self.claimsChange(currentText(replyID)) {
                await retry(question, into: replyID)
                actions = log.drain()
                if actions.isEmpty, Self.claimsChange(currentText(replyID)) {
                    mark(replyID) { $0.unverifiedClaim = true }
                }
            }
            attachActions(actions, to: replyID)

            var charts = chartLog.drain()
            var wasFallback = false

            // Eine Darstellung wurde erbeten, aber keine erzeugt: erst ein
            // zweiter Anlauf, dann zeichnet die App selbst. Auch eine
            // Anschlussfrage ohne eigenes Diagrammwort zählt, solange gerade
            // eine zu sehen war.
            let refines = lastAnswerHadChart(before: replyID) && ChartRequest.isRefinement(question)
            if charts.isEmpty, DashboardCharts.isRequested(in: question) || refines {
                if failure == nil {
                    await retry(question, into: replyID)
                    charts = chartLog.drain()
                }

                if charts.isEmpty {
                    let context = makeContext()
                    context.question = question
                    // Nur zeichnen, wenn der Inhalt aus der Frage hervorgeht.
                    // Sonst bliebe nur Raten.
                    if ChartRequest.hasKnownSubject(question, availableApps: context.charts.appNames()) {
                        let summary = context.charts.make(
                            question: question, form: "", content: "",
                            days: 0, apps: "", count: 0)
                        charts = chartLog.drain()
                        wasFallback = !charts.isEmpty
                        if wasFallback {
                            update(replyID, text: summary, streaming: false)
                            failure = nil
                        }
                    }
                    if charts.isEmpty && failure == nil {
                        mark(replyID) { $0.chartUnavailable = true }
                    }
                }
            }

            charts = Self.deduplicated(charts)
            if !charts.isEmpty {
                let correction = Self.correction(for: charts, answer: currentText(replyID))
                mark(replyID) {
                    $0.charts = charts
                    $0.chartCorrection = wasFallback ? nil : correction
                    $0.chartWasFallback = wasFallback
                }
            }

            if let failure {
                update(replyID, text: failure, streaming: false, failed: true)
            }
            isResponding = false
        }
    }

    /// Stellt dieselbe Frage noch einmal mit frischem Verlauf. Schlägt auch
    /// das fehl, bleibt es dabei – der Aufrufer arbeitet mit dem weiter, was
    /// in den Protokollen steht.
    private func retry(_ question: String, into replyID: UUID) async {
        backend?.reset()
        update(replyID, text: "", streaming: true)
        do {
            _ = try await backend?.respond(to: question) { [weak self] partial in
                self?.update(replyID, text: partial, streaming: true)
            }
        } catch {
            // Bewusst still: der Rückfall danach entscheidet.
        }
        update(replyID, text: nil, streaming: false)
    }

    /// Hatte die vorige Antwort eine Darstellung?
    private func lastAnswerHadChart(before id: UUID) -> Bool {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return false }
        return messages[..<index].last { $0.role == .assistant }?.charts.isEmpty == false
    }

    private func currentText(_ id: UUID) -> String {
        messages.first(where: { $0.id == id })?.text ?? ""
    }

    private func mark(_ id: UUID, _ change: (inout ChatMessage) -> Void) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        change(&messages[index])
    }

    /// Ruft das Modell das Zeichenwerkzeug zweimal mit derselben Absicht
    /// auf, entstünden zwei gleiche Diagramme untereinander.
    private static func deduplicated(_ charts: [ChartSpec]) -> [ChartSpec] {
        var seen = Set<String>()
        return charts.filter { spec in
            let key = "\(spec.title)|\(spec.subtitle)|\(spec.style)"
            return seen.insert(key).inserted
        }
    }

    /// Nennt der Text keine der Reihen, die das Diagramm zeigt, hat das
    /// Modell vermutlich seine eigenen Argumente nacherzählt. Dann wird
    /// darunter richtiggestellt, was wirklich abgebildet ist.
    private static func correction(for charts: [ChartSpec], answer: String) -> String? {
        let names = charts
            .filter { $0.style == .groupedBars }
            .flatMap { $0.series.map(\.name) }
        guard !names.isEmpty else { return nil }
        let lower = answer.lowercased()
        guard !names.contains(where: { lower.contains($0.lowercased()) }) else { return nil }
        return "Abgebildet sind: " + names.joined(separator: ", ") + "."
    }

    /// Erkennt Antworten, die eine Änderung am Dashboard behaupten.
    /// Bewusst auf Wendungen beschränkt, die eindeutig einen Eingriff meinen –
    /// bloßes „erledigt“ kommt auch in reinen Auskünften vor.
    private static func claimsChange(_ text: String) -> Bool {
        let lower = text.lowercased()
        let phrases = [
            "wurde angelegt", "wurde hinzugefügt", "wurde eingetragen", "wurde erstellt",
            "wurde gelöscht", "wurde entfernt", "wurde abgehakt", "wurde eingestuft",
            "wurde erfolgreich", "wurden erfolgreich", "habe ich angelegt",
            "habe ich hinzugefügt", "habe ich eingetragen", "habe ich gelöscht",
            "ist jetzt als erledigt", "erfolgreich angelegt", "erfolgreich hinzugefügt",
            "erfolgreich gelöscht", "erfolgreich eingetragen", "gilt ab sofort als"
        ]
        return phrases.contains { lower.contains($0) }
    }

    /// Hängt die tatsächlich vorgenommenen Änderungen an die Antwort.
    private func attachActions(_ actions: [AssistantAction], to id: UUID) {
        guard !actions.isEmpty, let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].actions = actions
    }

    /// Nimmt eine einzelne Änderung zurück.
    func undo(_ action: AssistantAction, in message: ChatMessage) {
        guard let messageIndex = messages.firstIndex(where: { $0.id == message.id }),
              let actionIndex = messages[messageIndex].actions.firstIndex(where: { $0.id == action.id }),
              !messages[messageIndex].actions[actionIndex].undone,
              let undo = action.undo
        else { return }
        undo()
        messages[messageIndex].actions[actionIndex].undone = true
        // Die Rücknahme selbst soll nicht als neue Änderung auftauchen.
        _ = log.drain()
    }

    private func update(_ id: UUID, text: String?, streaming: Bool, failed: Bool = false) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        if let text { messages[index].text = text }
        messages[index].isStreaming = streaming
        messages[index].failed = failed
        // Bleibt die Antwort leer, wäre eine leere Blase verwirrend.
        if !streaming, messages[index].text.isEmpty,
           messages[index].actions.isEmpty, messages[index].charts.isEmpty {
            messages[index].text = "Darauf habe ich keine Antwort gefunden."
            messages[index].failed = true
        }
    }

    func clear() {
        messages.removeAll()
        backend?.reset()
    }

    /// Prüft erneut – etwa nachdem Apple Intelligence eingeschaltet wurde.
    func refreshAvailability() {
        let backend = makeBackend()
        self.backend = backend
        self.unavailable = backend.map(\.unavailable) ?? .systemTooOld
    }

    private static func describe(_ error: Error) -> String {
        let text = String(describing: error).lowercased()
        if text.contains("guardrail") || text.contains("safety") {
            return "Diese Frage konnte das Modell nicht beantworten. Formuliere sie gern anders."
        }
        return "Es ist ein Fehler aufgetreten: \(error.localizedDescription)"
    }
}
