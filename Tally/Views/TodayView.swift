import SwiftUI
import SwiftData

/// The dashboard reads Health, while quick-log ranking uses only local template preferences and usage.
/// Secondary grouped surfaces preserve rounded-card separation in dark appearance.
struct TodayView: View {
    @Environment(HealthKitManager.self) private var health
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.openNutritionTrends) private var openNutritionTrends
    @Query private var drinks: [SavedDrink]
    @AppStorage("showCalories") private var showCalories = true
    @AppStorage("showSugar") private var showSugar = true
    @AppStorage("showProtein") private var showProtein = true
    @AppStorage("showCaffeine") private var showCaffeine = true
    // This preference affects presentation only; sodium is always available for entry and history.
    @AppStorage("showSodium") private var showSodium = false
    @State private var sheet: DrinkSheet?
    @State private var nutritionStatusHeight: CGFloat = 0
    @State private var drinkCardHeight: CGFloat = 0
    let openLibrary: () -> Void
    private var columns: [GridItem] { [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 280 : 155), spacing: 12)] }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    // The date sits directly on the grouped background; primary text keeps its contrast sufficient.
                    .font(.subheadline).foregroundStyle(.primary)
                if !health.permissionsRequested || !health.isAvailable { HealthAccessCard() }
                // Calories span the grid width; the remaining cards keep their adaptive layout.
                if showCalories || showProtein || showSugar || showCaffeine || showSodium {
                    Text("Nutrition Today").font(.title2.weight(.semibold))
                    VStack(spacing: 12) {
                        if showCalories { NutrientContributionLink(nutrient: .calories, nutrition: health.today) }
                        if showProtein || showSugar || showCaffeine || showSodium {
                            LazyVGrid(columns: columns, spacing: 12) {
                                if showProtein { NutrientContributionLink(nutrient: .protein, nutrition: health.today, fillRow: true, alignedStatusHeight: alignedStatusHeight) }
                                if showSugar { NutrientContributionLink(nutrient: .sugar, nutrition: health.today, fillRow: true, alignedStatusHeight: alignedStatusHeight) }
                                if showCaffeine { NutrientContributionLink(nutrient: .caffeine, nutrition: health.today, fillRow: true, alignedStatusHeight: alignedStatusHeight) }
                                if showSodium { NutrientContributionLink(nutrient: .sodium, nutrition: health.today, fillRow: true, alignedStatusHeight: alignedStatusHeight) }
                            }
                            .onPreferenceChange(NutritionStatusHeightKey.self) { nutritionStatusHeight = $0 }
                        }
                    }
                }
                // Trends stays available even when every Today card is hidden.
                Button { openNutritionTrends(nil) } label: { Label("View Trends", systemImage: "chart.bar") }
                    .accessibilityIdentifier("openNutritionTrends")
                // The breakdown remains accessible even when every dashboard card is hidden.
                NavigationLink {
                    DailyIntakeBreakdownView()
                } label: { Label("Daily Intake Breakdown", systemImage: "chart.bar.xaxis") }
                    .accessibilityIdentifier("dailyIntakeBreakdown")
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
                if DrinkOrdering.quickLog(drinks).isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(drinks.isEmpty ? "A home for your usuals" : "No active items").font(.headline)
                        Text(drinks.isEmpty ? "Save a food or drink once. Log its known nutrition again in a couple of taps." : "Restore an archived item from Library or add a new one.").font(.subheadline).foregroundStyle(.secondary)
                        Button(drinks.isEmpty ? "Add Your First Item" : "Add Item") { sheet = .add }.buttonStyle(.borderedProminent).foregroundStyle(Color(.systemBackground))
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(18)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
                } else {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(DrinkOrdering.quickLog(drinks)) { drink in
                            DrinkCard(drink: drink, alignedHeight: typeSize.isAccessibilitySize ? nil : drinkCardHeight) { sheet = .log(drink) }
                        }
                    }
                    // Keep all Quick Log cards even; accessibility sizes retain their natural height.
                    .onPreferenceChange(DrinkCardHeightKey.self) { drinkCardHeight = $0 }
                }
                Button { sheet = .quickAdd } label: {
                    Label("Quick Add a one-off entry", systemImage: "plus.circle").frame(maxWidth: .infinity, minHeight: 32)
                }.buttonStyle(.bordered)
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

    // Single-column accessibility layouts do not need cross-card spacing.
    private var alignedStatusHeight: CGFloat? { typeSize.isAccessibilitySize ? nil : nutritionStatusHeight }
}
