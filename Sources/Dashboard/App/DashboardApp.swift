import AppKit
import SwiftUI

/// Sorgt dafür, dass immer nur eine Kopie des Dashboards läuft.
///
/// macOS verhindert das nur für dieselbe Kopie am selben Ort. Liegt eine
/// zweite im Bauverzeichnis oder im Download-Ordner, startet sie zusätzlich –
/// und dann schreiben zwei Tracker dieselbe `activity.json`, jeder mit seinem
/// eigenen Stand. Wer zuletzt sichert, verwirft die Aufzeichnungen des anderen.
final class SingleInstanceDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        let myPID = ProcessInfo.processInfo.processIdentifier
        guard let id = Bundle.main.bundleIdentifier else { return }
        let other = NSWorkspace.shared.runningApplications.first {
            $0.bundleIdentifier == id && $0.processIdentifier != myPID
        }
        guard let other else { return }
        // Statt einer Fehlermeldung das bereits offene Fenster nach vorn holen –
        // so verhält sich die App wie jede andere, die schon läuft.
        other.activate()
        exit(0)
    }
}

@main
struct DashboardApp: App {
    @NSApplicationDelegateAdaptor(SingleInstanceDelegate.self) private var delegate

    @StateObject private var state = AppState()

    /// Bewusst hier und nicht in `AppState`: Änderungen an einem
    /// verschachtelten ObservableObject melden sich beim äußeren nicht an.
    /// Läge das Erscheinungsbild in `AppState`, würde diese Szene beim
    /// Umschalten nicht neu ausgewertet – `preferredColorScheme` bliebe
    /// stehen, und nur AppKit-gezeichnete Teile wechselten.
    @StateObject private var appearance = AppearanceSettings()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(state)
                .environmentObject(state.tasks)
                .environmentObject(state.tracker)
                .environmentObject(state.rules)
                .environmentObject(state.calendar)
                .environmentObject(state.plan)
                .environmentObject(state.notes)
                .environmentObject(state.assistant)
                .environmentObject(appearance)
                .preferredColorScheme(appearance.mode.colorScheme)
                .frame(minWidth: 940, minHeight: 620)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1180, height: 780)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Darstellung") {
                Picker("Erscheinungsbild", selection: Binding(
                    get: { appearance.mode },
                    set: { appearance.mode = $0 }
                )) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Label(mode.label, systemImage: mode.symbol).tag(mode)
                    }
                }
                Divider()
                Button("Erscheinungsbild wechseln") { appearance.cycle() }
                    .keyboardShortcut("d", modifiers: [.command, .shift])
            }
            CommandMenu("Bereich") {
                ForEach(DashboardSection.allCases) { section in
                    Button(section.title) { state.section = section }
                        .keyboardShortcut(KeyEquivalent(Character("\((DashboardSection.allCases.firstIndex(of: section) ?? 0) + 1)")),
                                          modifiers: .command)
                }
            }
        }

        Settings {
            SettingsView()
                .environmentObject(state.tracker)
                .environmentObject(state.rules)
                .environmentObject(state.calendar)
                .environmentObject(appearance)
                .preferredColorScheme(appearance.mode.colorScheme)
        }
    }
}
