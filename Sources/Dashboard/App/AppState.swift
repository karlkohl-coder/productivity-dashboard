import SwiftUI

/// Bereiche der Seitenleiste. Neue Module werden hier ergänzt –
/// `RootView` und die Navigation ziehen sich alles Übrige daraus.
enum DashboardSection: String, CaseIterable, Identifiable, Hashable {
    case overview, calendar, week, tasks, notes, tracker, stats, assistant

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return "Übersicht"
        case .calendar: return "Kalender"
        case .week:     return "Wochenplan"
        case .tasks:    return "Aufgaben"
        case .notes:    return "Notizen"
        case .tracker:  return "Tracker"
        case .stats:    return "Statistik"
        case .assistant: return "Assistenz"
        }
    }

    var symbol: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .calendar: return "calendar"
        case .week:     return "calendar.day.timeline.left"
        case .tasks:    return "checklist"
        case .notes:    return "note.text"
        case .tracker:  return "waveform.path.ecg"
        case .stats:    return "chart.bar"
        case .assistant: return "sparkles"
        }
    }
}

/// Gemeinsamer Einstiegspunkt für alle Dienste. Wird einmal erzeugt und
/// als EnvironmentObject nach unten gereicht.
@MainActor
final class AppState: ObservableObject {
    @Published var section: DashboardSection = .overview

    let tasks = TaskStore()
    let tracker = ActivityTracker()
    let rules = CategoryRules()
    let calendar = CalendarService()
    let plan = PlanStore()
    let notes = NotesStore()

    /// Protokolle dessen, was die Assistenz während einer Antwort erzeugt.
    let actionLog = ActionLog()
    let chartLog = ChartLog()

    /// Die Assistenz liest und schreibt über alle anderen Dienste. Der Umweg
    /// über eine Closure hält den Zugriff stets auf aktuellem Stand.
    lazy var assistant = AssistantEngine(log: actionLog, charts: chartLog) { [unowned self] in
        AssistantContext(
            query: DashboardQuery(tracker: tracker, rules: rules, tasks: tasks, calendar: calendar),
            commands: DashboardCommands(tasks: tasks, calendar: calendar, rules: rules,
                                        tracker: tracker, log: actionLog),
            charts: DashboardCharts(tracker: tracker, rules: rules, tasks: tasks,
                                    calendar: calendar, log: chartLog)
        )
    }
}
