import SwiftUI

/// Foreground refreshes update Health summaries and optional template sync without persisting a second consumption history.
struct RootView: View {
    @Environment(HealthKitManager.self) private var health
    @Environment(LibrarySyncManager.self) private var sync
    @Environment(\.scenePhase) private var scenePhase
    @State private var selected = 0
    var body: some View {
        TabView(selection: $selected) {
            Tab("Today", systemImage: "sun.max", value: 0) { NavigationStack { TodayView { selected = 1 } } }
            Tab("Library", systemImage: "list.bullet.clipboard", value: 1) { NavigationStack { DrinksView() } }
            Tab("History", systemImage: "clock", value: 2) { NavigationStack { HistoryView() } }
            Tab("Settings", systemImage: "gearshape", value: 3) { NavigationStack { SettingsView() } }
        }
        .task { await health.refresh(); await sync.startIfNeeded() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await health.refresh(); await sync.refreshAccount() } } }
    }
}
