import AppKit
import SwiftUI

/// Live-Ansicht des Produktivitätstrackers: was läuft gerade, wie ist es
/// eingestuft, und wie verteilt sich der heutige Tag auf die Anwendungen.
struct TrackerView: View {
    @EnvironmentObject private var tracker: ActivityTracker
    @EnvironmentObject private var rules: CategoryRules

    @State private var now = Date()
    @State private var groupByCategory = true
    private let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var todayUsage: [AppUsage] {
        tracker.usage(for: tracker.segments(on: now), rules: rules)
    }

    var body: some View {
        Page(title: "Tracker",
             subtitle: "Erfasst wird nur, welche App im Vordergrund ist – keine Fenstertitel, keine Inhalte.") {
            liveCard
            HStack(alignment: .top, spacing: Theme.Spacing.md) {
                usageCard
                runningCard.frame(width: 320)
            }
        } actions: {
            HStack(spacing: Theme.Spacing.md) {
                Toggle("Nach Einstufung gruppieren", isOn: $groupByCategory)
                    .toggleStyle(.checkbox)
                Toggle("Aufzeichnung", isOn: $tracker.isTracking)
                    .toggleStyle(.switch)
            }
            .controlSize(.small)
            .font(Theme.Font.caption)
        }
        .onReceive(clock) { now = $0 }
    }

    // MARK: - Aktuelle Sitzung

    private var liveCard: some View {
        Card {
            HStack(spacing: Theme.Spacing.lg) {
                AppIcon(bundleID: tracker.currentApp?.bundleID, size: 46)

                VStack(alignment: .leading, spacing: 3) {
                    Text(statusHeadline)
                        .font(.system(size: 17, weight: .medium))
                    Text(statusDetail)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Palette.textSecondary)
                }

                Spacer()

                if let bundleID = tracker.currentApp?.bundleID {
                    VStack(alignment: .trailing, spacing: 4) {
                        CategoryPicker(bundleID: bundleID)
                        Text(rules.assignment(for: bundleID).isAutomatic ? "automatisch eingestuft" : "von dir festgelegt")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.Palette.textTertiary)
                    }
                }
            }
            .frame(minHeight: 46)
        }
        .overlay(alignment: .leading) {
            // Farbkante, die die aktuelle Einstufung auf einen Blick zeigt.
            if let bundleID = tracker.currentApp?.bundleID, !tracker.isIdle, tracker.isTracking {
                UnevenRoundedRectangle(topLeadingRadius: Theme.Radius.lg,
                                       bottomLeadingRadius: Theme.Radius.lg,
                                       bottomTrailingRadius: 0, topTrailingRadius: 0)
                    .fill(rules.category(for: bundleID).color)
                    .frame(width: 4)
            }
        }
    }

    private var statusHeadline: String {
        guard tracker.isTracking else { return "Aufzeichnung pausiert" }
        if tracker.isIdle { return "Leerlauf" }
        return tracker.currentApp?.name ?? "Warte auf Aktivität …"
    }

    private var statusDetail: String {
        guard tracker.isTracking else { return "Es werden gerade keine Zeiten erfasst." }
        if tracker.isIdle { return "Keine Eingabe seit \(Int(tracker.idleThreshold / 60)) Minuten – die Zeit läuft nicht weiter." }
        guard let since = tracker.currentSince else { return "" }
        return "seit \(Format.time.string(from: since)) · \(Format.duration(now.timeIntervalSince(since)))"
    }

    // MARK: - Heutige Nutzung

    private var usageCard: some View {
        Card(title: "Heute nach Anwendung",
             subtitle: "Über die Einstufung rechts lässt sich jede App zuordnen oder auf „Automatisch“ zurücksetzen.") {
            if todayUsage.isEmpty {
                EmptyStateView(symbol: "hourglass", message: "Noch keine Zeiten erfasst.")
            } else if groupByCategory {
                groupedUsage
            } else {
                flatUsage(todayUsage)
            }
        }
    }

    private var groupedUsage: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            ForEach(ProductivityCategory.allCases) { cat in
                let apps = todayUsage.filter { $0.category == cat }
                if !apps.isEmpty {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                        HStack(spacing: Theme.Spacing.xs) {
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(cat.color)
                                .frame(width: 3, height: 12)
                            Text(cat.label)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(cat.color)
                            Text("· \(Format.duration(apps.reduce(0) { $0 + $1.seconds }))")
                                .font(Theme.Font.caption)
                                .foregroundStyle(Theme.Palette.textTertiary)
                            Spacer()
                        }
                        flatUsage(apps)
                    }
                }
            }
        }
    }

    private func flatUsage(_ apps: [AppUsage]) -> some View {
        VStack(spacing: 0) {
            ForEach(apps) { usage in
                AppUsageRow(usage: usage, maximum: todayUsage.first?.seconds ?? 1)
                if usage.id != apps.last?.id { Divider().opacity(0.35) }
            }
        }
    }

    // MARK: - Laufende Anwendungen

    private var runningCard: some View {
        Card(title: "Laufende Anwendungen", subtitle: "\(tracker.runningApps.count) aktiv") {
            VStack(spacing: 0) {
                ForEach(tracker.runningApps, id: \.processIdentifier) { app in
                    let bundleID = app.bundleIdentifier ?? ""
                    HStack(spacing: Theme.Spacing.sm) {
                        AppIcon(bundleID: bundleID, size: 18)
                        Text(app.localizedName ?? bundleID)
                            .font(Theme.Font.body)
                            .lineLimit(1)
                        Spacer(minLength: Theme.Spacing.xs)
                        CategoryPicker(bundleID: bundleID, compact: true)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }
}
