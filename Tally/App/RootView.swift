import SwiftUI

extension EnvironmentValues {
    // Shortcuts switch to the existing History stack from either summary surface.
    @Entry var openNutritionTrends = OpenNutritionTrendsAction { _ in }
}

struct OpenNutritionTrendsAction {
    let action: (Nutrient?) -> Void
    func callAsFunction(_ nutrient: Nutrient?) { action(nutrient) }
}

/// Foreground refreshes update Health summaries and optional template sync without persisting a second consumption history.
struct RootView: View {
    @Environment(HealthKitManager.self) private var health
    @Environment(LibrarySyncManager.self) private var sync
    @Environment(\.scenePhase) private var scenePhase
    @State private var selected = 0
    @State private var historySection = HistorySection.entries
    @State private var historyPath: [NutrientTrendDay] = []
    @AppStorage("trendNutrient") private var trendNutrient = Nutrient.caffeine

    var body: some View {
        TabView(selection: $selected) {
            Tab("Today", systemImage: "sun.max", value: 0) { NavigationStack { TodayView { selected = 1 } } }
            Tab("Library", systemImage: "list.bullet.clipboard", value: 1) { NavigationStack { DrinksView() } }
            Tab("History", systemImage: "clock", value: 2) {
                NavigationStack(path: $historyPath) {
                    HistoryView(section: $historySection, nutrient: $trendNutrient)
                        .navigationDestination(for: NutrientTrendDay.self) { route in
                            NutrientContributionsView(nutrient: route.nutrient, dateKey: route.date)
                        }
                }
            }
            Tab("Settings", systemImage: "gearshape", value: 3) { NavigationStack { SettingsView() } }
        }
        .environment(\.openNutritionTrends, OpenNutritionTrendsAction(action: openTrends))
        .task { await health.refresh(); await sync.startIfNeeded() }
        // UIKit covers midnight and clock changes. Foundation also posts when the system changes time zone.
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)
            .merge(with: NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange))) { _ in
            Task { await health.refresh() }
        }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await health.refresh(); await sync.refreshAccount() } } }
    }

    private func openTrends(_ nutrient: Nutrient?) {
        if let nutrient { trendNutrient = nutrient }
        historySection = .trends
        historyPath.removeAll()
        selected = 2
    }
}
