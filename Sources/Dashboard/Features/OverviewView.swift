import Charts
import SwiftUI

/// Startseite: verdichtet die wichtigsten Zahlen aller Module.
struct OverviewView: View {
    @EnvironmentObject private var tracker: ActivityTracker
    @EnvironmentObject private var rules: CategoryRules
    @EnvironmentObject private var tasks: TaskStore
    @EnvironmentObject private var calendar: CalendarService
    @EnvironmentObject private var state: AppState

    @State private var editorTarget: EventEditorTarget?

    private var today: DayStats {
        Statistics.dayStats(segments: tracker.segments(on: Date()), rules: rules, day: Date())
    }

    private var topApps: [AppUsage] {
        Array(tracker.usage(for: tracker.segments(on: Date()), rules: rules).prefix(5))
    }

    var body: some View {
        Page(title: greeting, subtitle: Format.fullDate.string(from: Date())) {
            TileGrid {
                MetricTile(label: "Aktive Zeit",
                           value: Format.durationShort(today.total),
                           detail: "heute erfasst")
                MetricTile(label: "Produktiv",
                           value: Format.durationShort(today.productive),
                           detail: today.total > 0 ? "\(Format.percent(today.productive / today.total)) der Zeit" : "noch keine Daten",
                           tint: Theme.Palette.productive)
                MetricTile(label: "Score",
                           value: "\(Int((today.score * 100).rounded()))",
                           detail: "von 100",
                           tint: Theme.Palette.accent)
                MetricTile(label: "Aufgaben offen",
                           value: "\(tasks.open.count)",
                           detail: "\(tasks.completedCount(on: Date())) heute erledigt")
            }

            HStack(alignment: .top, spacing: Theme.Spacing.md) {
                todayBreakdown
                agendaCard
            }

            HStack(alignment: .top, spacing: Theme.Spacing.md) {
                topAppsCard
                nextTasksCard
            }
        }
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<11:  return "Guten Morgen"
        case 11..<18: return "Guten Tag"
        default:      return "Guten Abend"
        }
    }

    // MARK: - Karten

    private var todayBreakdown: some View {
        Card(title: "Heute", subtitle: "Verteilung der erfassten Zeit") {
            if today.total == 0 {
                EmptyStateView(symbol: "hourglass",
                               message: "Noch keine Aktivität aufgezeichnet.\nDer Tracker läuft im Hintergrund mit.")
            } else {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    SegmentedBar(segments: [
                        (today.productive, ProductivityCategory.productive.color),
                        (today.neutral, ProductivityCategory.neutral.color),
                        (today.unproductive, ProductivityCategory.unproductive.color)
                    ], height: 10)

                    ForEach(ProductivityCategory.allCases) { cat in
                        HStack(spacing: Theme.Spacing.xs) {
                            Circle().fill(cat.color).frame(width: 7, height: 7)
                            Text(cat.label).font(Theme.Font.body)
                            Spacer()
                            Text(Format.duration(today.time(for: cat)))
                                .font(Theme.Font.body)
                                .foregroundStyle(Theme.Palette.textSecondary)
                                .monospacedDigit()
                        }
                    }
                }
            }
        }
    }

    private var agendaCard: some View {
        Card(title: "Termine heute") {
            switch calendar.access {
            case .granted:
                let events = calendar.events(on: Date())
                if events.isEmpty {
                    EmptyStateView(symbol: "calendar", message: "Keine Termine für heute.")
                } else {
                    VStack(spacing: Theme.Spacing.xs) {
                        ForEach(events.prefix(5), id: \.self) { event in
                            EventRow(event: event)
                                .contentShape(Rectangle())
                                .onTapGesture { editorTarget = EventEditorTarget(event: event, day: Date()) }
                        }
                    }
                }
            case .denied:
                EmptyStateView(symbol: "lock",
                               message: "Kein Kalenderzugriff.",
                               actionTitle: "Systemeinstellungen öffnen",
                               action: calendar.openSystemSettings)
            case .unknown:
                EmptyStateView(symbol: "calendar.badge.plus",
                               message: "Kalender noch nicht verbunden.",
                               actionTitle: "Zugriff erlauben",
                               action: calendar.requestAccess)
            }
        } trailing: {
            if calendar.access == .granted && !calendar.writableCalendars.isEmpty {
                Button {
                    editorTarget = EventEditorTarget(event: nil, day: Date())
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(Theme.Palette.accent)
                .help("Termin für heute anlegen")
            }
        }
        .onAppear { ensureCalendarLoaded() }
        .sheet(item: $editorTarget) { target in
            EventEditor(target: target) { editorTarget = nil }
                .environmentObject(calendar)
        }
    }

    private var topAppsCard: some View {
        Card(title: "Meistgenutzt heute") {
            if topApps.isEmpty {
                EmptyStateView(symbol: "app.dashed", message: "Noch nichts erfasst.")
            } else {
                VStack(spacing: Theme.Spacing.xs) {
                    ForEach(topApps) { usage in
                        AppUsageRow(usage: usage,
                                    maximum: topApps.first?.seconds ?? 1,
                                    showsPicker: false,
                                    barWidth: 60)
                    }
                }
            }
        }
    }

    private var nextTasksCard: some View {
        Card(title: "Als Nächstes") {
            let next = Array(tasks.open.prefix(5))
            if next.isEmpty {
                EmptyStateView(symbol: "checkmark.circle",
                               message: "Keine offenen Aufgaben.",
                               actionTitle: "Aufgabe anlegen",
                               action: { state.section = .tasks })
            } else {
                VStack(spacing: 0) {
                    ForEach(next) { task in
                        TaskRow(task: task, compact: true)
                    }
                }
            }
        }
    }

    private func ensureCalendarLoaded() {
        let cal = Calendar.german
        let start = cal.startOfDay(for: Date())
        if let end = cal.date(byAdding: .day, value: 14, to: start) {
            calendar.load(from: start, to: end)
        }
    }
}
