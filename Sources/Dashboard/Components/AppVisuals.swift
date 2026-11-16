import AppKit
import SwiftUI

/// App-Icons aus dem jeweiligen Bundle, mit Zwischenspeicher – die Listen
/// aktualisieren sich sekündlich, ein Plattenzugriff pro Bild reicht.
@MainActor
enum IconCache {
    private static var cache: [String: NSImage?] = [:]

    static func icon(for bundleID: String?) -> NSImage? {
        guard let bundleID else { return nil }
        if let cached = cache[bundleID] { return cached }
        let image = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            .map { NSWorkspace.shared.icon(forFile: $0.path) }
        cache[bundleID] = image
        return image
    }
}

struct AppIcon: View {
    let bundleID: String?
    var size: CGFloat = 20

    var body: some View {
        Group {
            if let image = IconCache.icon(for: bundleID) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
            } else {
                RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                    .fill(Theme.Palette.hairline)
                    .overlay(
                        Image(systemName: "app.dashed")
                            .font(.system(size: size * 0.5))
                            .foregroundStyle(Theme.Palette.textTertiary)
                    )
            }
        }
        .frame(width: size, height: size)
    }
}

/// Deutlich sichtbare Einstufung: getöntes Feld mit Symbol und Text.
/// `showsAutomatic` blendet zusätzlich ein, ob die Zuordnung hergeleitet wurde.
struct CategoryBadge: View {
    let assignment: CategoryAssignment
    var compact = false
    var showsAutomatic = true

    private var category: ProductivityCategory { assignment.category }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: category.symbol)
                .font(.system(size: compact ? 8 : 9, weight: .bold))
            if !compact {
                Text(category.label)
                    .font(.system(size: 11, weight: .medium))
            }
            if showsAutomatic && assignment.isAutomatic {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: compact ? 7 : 8))
                    .opacity(0.55)
            }
        }
        .foregroundStyle(category.color)
        .padding(.horizontal, compact ? 5 : 7)
        .padding(.vertical, compact ? 2 : 3)
        .background(category.color.opacity(0.14), in: Capsule())
        .overlay(Capsule().strokeBorder(category.color.opacity(0.28), lineWidth: 1))
        .help(assignment.explanation)
    }
}

/// Menü zur Einstufung einer App – inklusive „Automatisch“ als Standard.
struct CategoryPicker: View {
    let bundleID: String
    var compact = false

    @EnvironmentObject private var rules: CategoryRules

    var body: some View {
        let assignment = rules.assignment(for: bundleID)
        let choice = rules.choice(for: bundleID)

        Menu {
            Button {
                rules.apply(.automatic, to: bundleID)
            } label: {
                Label(choice == .automatic
                      ? "Automatisch ✓ (\(assignment.category.label))"
                      : "Automatisch",
                      systemImage: "wand.and.stars")
            }
            Divider()
            ForEach(ProductivityCategory.allCases) { cat in
                Button {
                    rules.apply(.fixed(cat), to: bundleID)
                } label: {
                    Label(choice == .fixed(cat) ? "\(cat.label) ✓" : cat.label,
                          systemImage: cat.symbol)
                }
            }
        } label: {
            CategoryBadge(assignment: assignment, compact: compact)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

/// Standardzeile für eine erfasste Anwendung: Icon, Name, Balken, Dauer,
/// Einstufung. Wird in Übersicht, Tracker und Statistik verwendet.
struct AppUsageRow: View {
    let usage: AppUsage
    let maximum: TimeInterval
    var showsPicker = true
    var barWidth: CGFloat = 80

    @EnvironmentObject private var rules: CategoryRules

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            AppIcon(bundleID: usage.bundleID, size: 20)

            Text(usage.appName)
                .font(Theme.Font.body)
                .lineLimit(1)

            Spacer(minLength: Theme.Spacing.xs)

            GeometryReader { geo in
                Capsule()
                    .fill(usage.category.color.opacity(0.45))
                    .frame(width: max(3, geo.size.width * usage.seconds / max(maximum, 1)))
                    .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(width: barWidth, height: 6)

            Text(Format.durationShort(usage.seconds))
                .font(Theme.Font.caption)
                .monospacedDigit()
                .foregroundStyle(Theme.Palette.textSecondary)
                .frame(width: 54, alignment: .trailing)

            if showsPicker {
                CategoryPicker(bundleID: usage.bundleID)
                    .frame(width: 116, alignment: .trailing)
            } else {
                CategoryBadge(assignment: rules.assignment(for: usage.bundleID), compact: true)
            }
        }
        .padding(.horizontal, Theme.Spacing.xs)
        .padding(.vertical, 4)
        .hoverRow()
    }
}
