import SwiftUI

struct RootView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $state.section)
                .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        } detail: {
            detail
                .background(Theme.Palette.canvas)
        }
        .navigationSplitViewStyle(.balanced)
    }

    @ViewBuilder
    private var detail: some View {
        switch state.section {
        case .overview: OverviewView()
        case .calendar: CalendarPage()
        case .week:     WeekPlanView()
        case .tasks:    TasksView()
        case .notes:    NotesView()
        case .tracker:  TrackerView()
        case .stats:    StatsView()
        case .assistant: AssistantView()
        }
    }
}

struct SidebarView: View {
    @Binding var selection: DashboardSection
    @EnvironmentObject private var tracker: ActivityTracker

    var body: some View {
        List(selection: $selection) {
            SwiftUI.Section {
                ForEach(DashboardSection.allCases) { item in
                    Label(item.title, systemImage: item.symbol)
                        .tag(item)
                }
            } header: {
                Text("Dashboard")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.textTertiary)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            TrackingIndicator()
                .padding(Theme.Spacing.sm)
        }
    }
}

/// Kleiner Statusfuß: zeigt, ob und was gerade aufgezeichnet wird.
struct TrackingIndicator: View {
    @EnvironmentObject private var tracker: ActivityTracker
    @EnvironmentObject private var appearance: AppearanceSettings

    @EnvironmentObject private var rules: CategoryRules

    /// Der Punkt trägt die Farbe der aktuellen Einstufung – der Status ist
    /// damit auch aus dem Augenwinkel ablesbar.
    private var statusColor: Color {
        guard tracker.isTracking else { return Theme.Palette.textTertiary }
        if tracker.isIdle { return Theme.Palette.textTertiary }
        guard let bundleID = tracker.currentApp?.bundleID else { return Theme.Palette.neutral }
        return rules.category(for: bundleID).color
    }

    private var statusText: String {
        guard tracker.isTracking else { return "Pausiert" }
        if tracker.isIdle { return "Leerlauf" }
        return tracker.currentApp?.name ?? "Warte …"
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            if let bundleID = tracker.currentApp?.bundleID, tracker.isTracking, !tracker.isIdle {
                AppIcon(bundleID: bundleID, size: 14)
                Circle()
                    .fill(statusColor)
                    .frame(width: 6, height: 6)
            } else {
                Circle()
                    .fill(statusColor)
                    .frame(width: 7, height: 7)
            }
            Text(statusText)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Palette.textSecondary)
                .lineLimit(1)
            Spacer(minLength: 0)
            Button {
                tracker.isTracking.toggle()
            } label: {
                Image(systemName: tracker.isTracking ? "pause.fill" : "play.fill")
                    .font(.system(size: 9))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(Theme.Palette.textTertiary)
            .help(tracker.isTracking ? "Aufzeichnung pausieren" : "Aufzeichnung fortsetzen")

            Button { appearance.cycle() } label: {
                Image(systemName: appearance.mode.symbol)
                    .font(.system(size: 10))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(Theme.Palette.textTertiary)
            .help("Erscheinungsbild: \(appearance.mode.label) (⇧⌘D)")
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, Theme.Spacing.xs)
        .background(Theme.Palette.hairline, in: Capsule())
    }
}

/// Einheitliches Seitengerüst: Titel, optionale Aktionen, scrollender Inhalt.
struct Page<Content: View, Actions: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var content: () -> Content
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(Theme.Font.pageTitle)
                        if let subtitle {
                            Text(subtitle)
                                .font(Theme.Font.body)
                                .foregroundStyle(Theme.Palette.textSecondary)
                        }
                    }
                    Spacer(minLength: Theme.Spacing.md)
                    actions()
                }
                content()
            }
            .padding(Theme.Spacing.xl)
            .frame(maxWidth: 1100, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}

extension Page where Actions == EmptyView {
    init(title: String, subtitle: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.init(title: title, subtitle: subtitle, content: content, actions: { EmptyView() })
    }
}

/// Adaptives Raster für Kacheln.
struct TileGrid<Content: View>: View {
    var minWidth: CGFloat = 220
    @ViewBuilder var content: () -> Content

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: minWidth), spacing: Theme.Spacing.md)],
                  spacing: Theme.Spacing.md) {
            content()
        }
    }
}
