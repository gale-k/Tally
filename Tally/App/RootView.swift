import SwiftUI

/// Foreground and manual refreshes pick up changes made in Health or another app without persisting a second history.
struct RootView: View {
    @Environment(HealthKitManager.self) private var health
    @Environment(\.scenePhase) private var scenePhase
    @State private var selected = 0
    var body: some View {
        TabView(selection: $selected) {
            Tab("Today", systemImage: "sun.max", value: 0) { NavigationStack { TodayView { selected = 1 } } }
            Tab("Drinks", systemImage: "cup.and.saucer", value: 1) { NavigationStack { DrinksView() } }
            Tab("History", systemImage: "clock", value: 2) { NavigationStack { HistoryView() } }
            Tab("Settings", systemImage: "gearshape", value: 3) { NavigationStack { SettingsView() } }
        }
        .task { await health.refresh() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await health.refresh() } } }
    }
}
