import SwiftUI

/// Reads the same transient Health totals as Today; opening this screen never requests new types.
struct DailyIntakeBreakdownView: View {
    @Environment(HealthKitManager.self) private var health
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if health.isLoading { ProgressView("Refreshing Apple Health") }
                if let error = health.queryError {
                    Label("Health refresh needs attention", systemImage: "exclamationmark.circle").font(.headline)
                    Text(error)
                    Text("Any totals still shown are from the last successful refresh.").font(.caption)
                    Button("Try Again") { Task { await health.refresh() } }
                }
                HealthReadNote()
                // Short card labels describe tracking choices; defaults are not personalised medical limits.
                Text("Targets and maximums are tracking comparisons. Adult defaults are general starting points, not personalised advice or universal safe limits.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Differences use visible totals only. Missing or restricted data cannot establish a remaining allowance.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(DailyIntakeReference.all) { reference in
                    NutrientContributionLink(nutrient: reference.nutrient, nutrition: health.today)
                }
                NavigationLink("Edit Daily Intake Settings") { DailyIntakeSettingsView() }
            }.padding(20)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Daily Intake")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await health.refresh() }
    }
}
