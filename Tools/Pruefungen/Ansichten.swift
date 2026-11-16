import AppKit
import SwiftUI

// Baut jede Ansicht einmal mit vollständig leerem Datenverzeichnis auf –
// der Zustand, in dem die App auf einem fremden Mac zum ersten Mal startet.
// Ein Absturz dabei wäre sonst erst beim Benutzer aufgefallen.

@MainActor
private func zeichne<V: View>(_ name: String, _ view: V, hoehe: CGFloat = 900) {
    let eingepackt = view
        .frame(width: 1180, height: hoehe)
        .background(Theme.Palette.canvas)
    let host = NSHostingView(rootView: eingepackt)
    host.frame = NSRect(x: 0, y: 0, width: 1180, height: hoehe)
    let fenster = NSWindow(contentRect: host.frame, styleMask: [.borderless],
                           backing: .buffered, defer: false)
    fenster.contentView = host
    fenster.orderBack(nil)
    RunLoop.main.run(until: Date().addingTimeInterval(0.8))
    if let inhalt = fenster.contentView,
       let bild = inhalt.bitmapImageRepForCachingDisplay(in: inhalt.bounds) {
        inhalt.cacheDisplay(in: inhalt.bounds, to: bild)
    }
    fenster.orderOut(nil)
    print("  ok   \(name)")
}

@main
struct Ansichten {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.finishLaunching()

        MainActor.assumeIsolated {
            let state = AppState()
            let erscheinungsbild = AppearanceSettings()
            let assistenz = state.assistant

            guard state.tracker.segments.isEmpty, state.notes.notes.isEmpty else {
                print("  FEHLER: Datenverzeichnis ist nicht leer – Prüfung abgebrochen.")
                exit(1)
            }

            func umgeben<V: View>(_ v: V) -> some View {
                v.environmentObject(state)
                    .environmentObject(state.tasks)
                    .environmentObject(state.tracker)
                    .environmentObject(state.rules)
                    .environmentObject(state.calendar)
                    .environmentObject(state.plan)
                    .environmentObject(state.notes)
                    .environmentObject(assistenz)
                    .environmentObject(erscheinungsbild)
            }

            zeichne("Übersicht", umgeben(OverviewView()))
            zeichne("Kalender", umgeben(CalendarPage()))
            zeichne("Wochenplan", umgeben(WeekPlanView()))
            zeichne("Aufgaben", umgeben(TasksView()))
            zeichne("Notizen", umgeben(NotesView()), hoehe: 700)
            zeichne("Tracker", umgeben(TrackerView()))
            zeichne("Statistik", umgeben(StatsView()), hoehe: 1400)
            zeichne("Assistenz", umgeben(AssistantView()))
            zeichne("Einstellungen", umgeben(SettingsView()), hoehe: 460)

            print("\n  Alle Ansichten ohne Absturz aufgebaut.")
        }
    }
}
