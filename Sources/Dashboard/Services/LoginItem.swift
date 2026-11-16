import AppKit
import ServiceManagement
import SwiftUI

/// Startet das Dashboard automatisch bei der Anmeldung.
///
/// Ohne das zeichnet der Tracker nur auf, wenn jemand die App von Hand
/// öffnet – und lückenhafte Tage machen jeden Vergleich wertlos.
@MainActor
final class LoginItem: ObservableObject {

    enum State: Equatable {
        case off
        case on
        /// macOS verlangt eine Bestätigung in den Systemeinstellungen.
        case needsApproval
        case failed(String)
    }

    @Published private(set) var state: State = .off

    init() { refresh() }

    var isOn: Bool { state == .on }

    /// Ein Anmeldeobjekt zeigt auf einen festen Pfad. Liegt die App noch im
    /// Bauverzeichnis, bricht der automatische Start, sobald sie umzieht.
    var isInApplicationsFolder: Bool {
        Bundle.main.bundleURL.path.hasPrefix("/Applications/")
    }

    var bundlePath: String { Bundle.main.bundleURL.path }

    func refresh() {
        switch SMAppService.mainApp.status {
        case .enabled:           state = .on
        case .requiresApproval:  state = .needsApproval
        case .notRegistered:     state = .off
        case .notFound:          state = .failed("Die App wurde vom System nicht gefunden.")
        @unknown default:        state = .off
        }
    }

    func set(_ enabled: Bool) {
        do {
            if enabled {
                // Ein zweites Registrieren wirft; vorher aufräumen.
                if SMAppService.mainApp.status == .enabled {
                    try? SMAppService.mainApp.unregister()
                }
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            refresh()
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// Öffnet den Bereich „Anmeldeobjekte“ der Systemeinstellungen.
    func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}
