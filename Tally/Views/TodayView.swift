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
    @AppStorage("showProtein") private var showProtein = true
    @AppStorage("showCaffeine") private var showCaffeine = true
    // This preference affects presentation only; sodium is always available for entry and history.
    @AppStorage("showSodium") private var showSodium = false
    @State private var sheet: DrinkSheet?
    let openLibrary: () -> Void
    private var target: Double { storedTarget.isFinite && storedTarget > 0 ? storedTarget : 400 }
    private var columns: [GridItem] { [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 280 : 155), spacing: 12)] }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    // The date sits directly on the grouped background; primary text keeps its contrast sufficient.
                    .font(.subheadline).foregroundStyle(.primary)
                if !health.permissionsRequested || !health.isAvailable { HealthAccessCard() }
                // Equal-weight cards avoid treating caffeine as a required part of every diet entry.
                if showCalories || showProtein || showSugar || showCaffeine || showSodium {
                    Text("Nutrition Today").font(.title2.weight(.semibold))
                    LazyVGrid(columns: columns, spacing: 12) {
                        if showCalories { SecondaryNutritionCard(nutrient: .calories, nutrition: health.today) }
                        if showProtein { SecondaryNutritionCard(nutrient: .protein, nutrition: health.today) }
                        if showSugar { SecondaryNutritionCard(nutrient: .sugar, nutrition: health.today) }
                        if showCaffeine { CaffeineSummaryCard(nutrition: health.today, target: target) }
                        if showSodium { SecondaryNutritionCard(nutrient: .sodium, nutrition: health.today) }
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
                    Button("Library", action: openLibrary).font(.subheadline)
                }
                if drinks.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("A home for your usuals").font(.headline)
                        Text("Save a food or drink once. Log its known nutrition again in a couple of taps.").font(.subheadline).foregroundStyle(.secondary)
                        Button("Add Your First Item") { sheet = .add }.buttonStyle(.borderedProminent).foregroundStyle(Color(.systemBackground))
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
                    Label("Quick Add a one-off entry", systemImage: "plus.circle").frame(maxWidth: .infinity, minHeight: 32)
                }.buttonStyle(.bordered)
                if showCaffeine { CaffeineTrendView(days: health.caffeineDays) }
            }.padding(20)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Today")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if health.isLoading { ProgressView().accessibilityLabel("Refreshing Apple Health") }
                Menu {
                    Button("Quick Add", systemImage: "plus.circle") { sheet = .quickAdd }
                    Button("Add Saved Item", systemImage: "plus") { sheet = .add }
                } label: { Image(systemName: "plus") }.accessibilityLabel("Add food or drink")
            }
        }
        .refreshable { await health.refresh() }
        .drinkSheets($sheet)
    }
}
