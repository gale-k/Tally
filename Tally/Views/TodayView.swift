import SwiftUI
import SwiftData

/// The dashboard reads Health, while quick-log ranking uses only local template preferences and usage.
/// Secondary grouped surfaces preserve rounded-card separation in dark appearance.
struct TodayView: View {
    @Environment(HealthKitManager.self) private var health
    @Environment(\.dynamicTypeSize) private var typeSize
    @Query private var drinks: [SavedDrink]
    @AppStorage("dailyCaffeineTarget") private var storedTarget = 400.0
    @AppStorage("showCalories") private var showCalories = true
    @AppStorage("showSugar") private var showSugar = true
    @State private var sheet: DrinkSheet?
    let openLibrary: () -> Void
    private var target: Double { storedTarget.isFinite && storedTarget > 0 ? storedTarget : 400 }
    private var columns: [GridItem] { [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 280 : 155), spacing: 12)] }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .font(.subheadline).foregroundStyle(.secondary)
                if !health.permissionsRequested || !health.isAvailable { HealthAccessCard() }
                CaffeineSummaryCard(nutrition: health.today, target: target)
                if showCalories || showSugar {
                    LazyVGrid(columns: columns, spacing: 12) {
                        if showCalories { SecondaryNutritionCard(nutrient: .calories, nutrition: health.today) }
                        if showSugar { SecondaryNutritionCard(nutrient: .sugar, nutrition: health.today) }
                    }
                }
                if let error = health.queryError {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Health refresh needs attention", systemImage: "exclamationmark.circle").font(.headline)
                        Text(error).font(.subheadline)
                        Text("Any totals still shown are from the last successful refresh.").font(.caption)
                        Button("Try Again") { Task { await health.refresh() } }
                    }.padding(16).background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
                }
                HealthReadNote()
                HStack {
                    Text("Quick Log").font(.title2.weight(.semibold))
                    Spacer()
                    Button("All Drinks", action: openLibrary).font(.subheadline)
                }
                if drinks.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("A home for your usuals").font(.headline)
                        Text("Save a drink once. The next one is just a couple of taps away.").font(.subheadline).foregroundStyle(.secondary)
                        Button("Add Your First Drink") { sheet = .add }.buttonStyle(.borderedProminent)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(18)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
                } else {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(DrinkOrdering.quickLog(drinks)) { drink in
                            DrinkCard(drink: drink) { sheet = .log(drink) }
                        }
                    }
                }
                Button { sheet = .quickAdd } label: {
                    Label("Quick Add a one-off drink", systemImage: "bolt.badge.plus").frame(maxWidth: .infinity, minHeight: 32)
                }.buttonStyle(.bordered)
                CaffeineTrendView(days: health.caffeineDays)
            }.padding(20)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Today")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if health.isLoading { ProgressView().accessibilityLabel("Refreshing Apple Health") }
                Menu {
                    Button("Quick Add", systemImage: "bolt.badge.plus") { sheet = .quickAdd }
                    Button("Add Saved Drink", systemImage: "plus") { sheet = .add }
                } label: { Image(systemName: "plus") }.accessibilityLabel("Add a drink")
            }
        }
        .refreshable { await health.refresh() }
        .drinkSheets($sheet)
    }
}
