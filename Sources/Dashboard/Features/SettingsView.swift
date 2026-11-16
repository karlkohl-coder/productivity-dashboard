import AppKit
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            AppearanceSettingsView()
                .tabItem { Label("Darstellung", systemImage: "paintbrush") }
            TrackingSettings()
                .tabItem { Label("Tracking", systemImage: "waveform.path.ecg") }
            RulesSettings()
                .tabItem { Label("Einstufung", systemImage: "slider.horizontal.3") }
            DataSettings()
                .tabItem { Label("Daten", systemImage: "externaldrive") }
        }
        .frame(width: 520, height: 420)
    }
}

private struct AppearanceSettingsView: View {
    @EnvironmentObject private var appearance: AppearanceSettings

    var body: some View {
        Form {
            Picker("Erscheinungsbild", selection: $appearance.mode) {
                ForEach(AppearanceMode.allCases) { mode in
                    Label(mode.label, systemImage: mode.symbol).tag(mode)
                }
            }
            .pickerStyle(.inline)

            Text("„System“ folgt der Einstellung von macOS und wechselt mit ihr. Umschalten geht auch mit ⇧⌘D oder über das Menü „Darstellung“.")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .formStyle(.grouped)
        .padding()
    }
}

private struct TrackingSettings: View {
    @EnvironmentObject private var tracker: ActivityTracker
    @EnvironmentObject private var calendar: CalendarService
    @StateObject private var loginItem = LoginItem()

    var body: some View {
        Form {
            Toggle("Bei der Anmeldung starten", isOn: Binding(
                get: { loginItem.isOn },
                set: { loginItem.set($0) }
            ))
            loginItemHint

            Divider().padding(.vertical, Theme.Spacing.xs)

            Toggle("Aktivität aufzeichnen", isOn: $tracker.isTracking)
            Picker("Leerlauf ab", selection: $tracker.idleThreshold) {
                Text("1 Minute").tag(TimeInterval(60))
                Text("2 Minuten").tag(TimeInterval(120))
                Text("5 Minuten").tag(TimeInterval(300))
                Text("10 Minuten").tag(TimeInterval(600))
            }
            Text("Ohne Maus- oder Tastatureingabe pausiert die Erfassung automatisch.")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Palette.textTertiary)

            Divider().padding(.vertical, Theme.Spacing.xs)

            LabeledContent("Kalender") {
                switch calendar.access {
                case .granted: Text("Verbunden").foregroundStyle(Theme.Palette.productive)
                case .denied:  Button("Systemeinstellungen öffnen", action: calendar.openSystemSettings)
                case .unknown: Button("Zugriff erlauben", action: calendar.requestAccess)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear { loginItem.refresh() }
    }

    @ViewBuilder
    private var loginItemHint: some View {
        switch loginItem.state {
        case .needsApproval:
            HStack(spacing: Theme.Spacing.xs) {
                Text("macOS möchte das noch bestätigt haben.")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.unproductive)
                Button("Anmeldeobjekte öffnen", action: loginItem.openSystemSettings)
                    .buttonStyle(.link)
                    .font(Theme.Font.caption)
            }
        case .failed(let message):
            Text(message)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Palette.unproductive)
                .fixedSize(horizontal: false, vertical: true)
        default:
            if !loginItem.isInApplicationsFolder {
                Text("Die App liegt unter \(loginItem.bundlePath). Ein Anmeldeobjekt zeigt auf diesen festen Pfad – zieh sie nach „Programme“, sonst bricht der automatische Start beim nächsten Umzug.")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Ohne automatischen Start zeichnet der Tracker nur auf, solange die App offen ist – lückenhafte Tage verzerren jeden Vergleich.")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Eine bekannte Anwendung in der Einstufungsliste.
private struct KnownApp: Identifiable, Hashable {
    var id: String { bundleID }
    let bundleID: String
    let name: String
}

private struct RulesSettings: View {
    @EnvironmentObject private var rules: CategoryRules
    @EnvironmentObject private var tracker: ActivityTracker

    @State private var search = ""
    @State private var filter: Filter = .all

    private enum Filter: String, CaseIterable, Identifiable {
        case all, manual, automatic
        var id: String { rawValue }
        var label: String {
            switch self {
            case .all:       return "Alle"
            case .manual:    return "Manuell"
            case .automatic: return "Automatisch"
            }
        }
    }

    /// Alle je gesehenen Apps – aus Historie, laufenden Prozessen und
    /// eigenen Zuordnungen.
    private var knownApps: [KnownApp] {
        var map: [String: String] = [:]
        for seg in tracker.segments { map[seg.bundleID] = seg.appName }
        for app in tracker.runningApps {
            if let id = app.bundleIdentifier { map[id] = app.localizedName ?? id }
        }
        for id in rules.manual.keys where map[id] == nil {
            map[id] = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
                .flatMap { FileManager.default.displayName(atPath: $0.path) } ?? id
        }
        return map.map { KnownApp(bundleID: $0.key, name: $0.value) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var visibleApps: [KnownApp] {
        knownApps.filter { app in
            let matchesSearch = search.isEmpty
                || app.name.localizedCaseInsensitiveContains(search)
                || app.bundleID.localizedCaseInsensitiveContains(search)
            let isAuto = rules.assignment(for: app.bundleID).isAutomatic
            let matchesFilter: Bool
            switch filter {
            case .all:       matchesFilter = true
            case .manual:    matchesFilter = !isAuto
            case .automatic: matchesFilter = isAuto
            }
            return matchesSearch && matchesFilter
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            List {
                ForEach(visibleApps) { app in
                    AppRuleRow(app: app)
                }
            }
            .listStyle(.inset)

            footer
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Jede Anwendung ist standardmäßig auf „Automatisch“. Das Dashboard leitet die Einstufung dann aus einer Liste bekannter Programme und aus der App-Kategorie ab, die die Anwendung selbst meldet. Eine eigene Auswahl überschreibt das dauerhaft.")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Toggle("App-Kategorie des Programms mitverwenden", isOn: $rules.usesAppCategoryHeuristic)
                .toggleStyle(.checkbox)
                .font(Theme.Font.body)

            Picker("Automatisch, wenn nichts bekannt ist:", selection: $rules.fallback) {
                ForEach(ProductivityCategory.allCases) { c in Text(c.label).tag(c) }
            }

            HStack(spacing: Theme.Spacing.sm) {
                Picker("", selection: $filter) {
                    ForEach(Filter.allCases) { f in Text(f.label).tag(f) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 220)

                TextField("Suchen …", text: $search)
                    .textFieldStyle(.roundedBorder)
            }
        }
        .controlSize(.small)
        .padding(Theme.Spacing.md)
    }

    private var footer: some View {
        HStack {
            Text("\(rules.manualCount) von \(knownApps.count) Anwendungen manuell eingestuft")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Palette.textTertiary)
            Spacer()
            Button("Alle auf Automatisch") { rules.resetAllToAutomatic() }
                .controlSize(.small)
                .disabled(rules.manualCount == 0)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.xs)
    }
}

/// Zeile der Einstufungsliste: Icon, Name, Herkunft der Einstufung, Auswahl.
private struct AppRuleRow: View {
    let app: KnownApp
    @EnvironmentObject private var rules: CategoryRules

    var body: some View {
        let assignment = rules.assignment(for: app.bundleID)

        HStack(spacing: Theme.Spacing.sm) {
            AppIcon(bundleID: app.bundleID, size: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(app.name).font(Theme.Font.body)
                Text(assignment.explanation)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.Palette.textTertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: Theme.Spacing.sm)

            CategoryBadge(assignment: assignment, compact: true)

            Picker("", selection: Binding(
                get: { rules.choice(for: app.bundleID) },
                set: { rules.apply($0, to: app.bundleID) }
            )) {
                ForEach(CategoryChoice.allCases) { choice in
                    Text(choice.label).tag(choice)
                }
            }
            .labelsHidden()
            .frame(width: 130)
            .controlSize(.small)
        }
        .padding(.vertical, 2)
    }
}

private struct DataSettings: View {
    @EnvironmentObject private var tracker: ActivityTracker
    @State private var confirmClear = false

    var body: some View {
        Form {
            LabeledContent("Speicherort") {
                Button(JSONStore.directory.path) {
                    NSWorkspace.shared.open(JSONStore.directory)
                }
                .buttonStyle(.link)
                .font(Theme.Font.caption)
            }
            LabeledContent("Aufgezeichnete Segmente") {
                Text("\(tracker.segments.count)").monospacedDigit()
            }
            Button("Aufzeichnungen löschen …", role: .destructive) { confirmClear = true }
        }
        .formStyle(.grouped)
        .padding()
        .alert("Alle Aufzeichnungen löschen?", isPresented: $confirmClear) {
            Button("Abbrechen", role: .cancel) {}
            Button("Löschen", role: .destructive) { tracker.clearHistory() }
        } message: {
            Text("Die erfassten Zeiten werden unwiderruflich entfernt. Aufgaben bleiben erhalten.")
        }
    }
}
