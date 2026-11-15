import SwiftUI

/// Caffeine shares the same comparison and optional-value behaviour as the other dashboard cards.
struct CaffeineSummaryCard: View {
    let nutrition: NutritionValues
    var body: some View { SecondaryNutritionCard(nutrient: .caffeine, nutrition: nutrition) }
}

/// The original visibility controls still govern these equal-weight dashboard cards.
struct SecondaryNutritionCard: View {
    let nutrient: Nutrient
    let nutrition: NutritionValues
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(nutrient == .sugar ? "Total Sugars" : nutrient.title).font(.subheadline).foregroundStyle(.secondary)
            Text(nutrition.formatted(nutrient) ?? "— \(nutrient.unit)")
                .font(.title3.weight(.semibold)).monospacedDigit()
                .accessibilityLabel(amountLabel)
                .accessibilityIdentifier(nutrient == .caffeine ? "todayCaffeine" : "today.\(nutrient.rawValue)")
            if let reference = DailyIntakeReference.all.first(where: { $0.nutrient == nutrient }) {
                DailyIntakeComparison(reference: reference, nutrition: nutrition)
            }
            Text("Apple Health · all sources").font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
    }
    // Preserve existing amount labels; the neighbouring title already identifies secondary nutrients.
    private var amountLabel: String {
        guard let amount = nutrition.formatted(nutrient) else { return "No visible \(nutrient.title.lowercased()) data today" }
        return nutrient == .caffeine ? "Caffeine today, \(amount)" : amount
    }
}

/// Independent preference observation updates existing cards immediately after Settings changes.
struct DailyIntakeComparison: View {
    let reference: DailyIntakeReference
    let nutrition: NutritionValues
    @AppStorage private var value: Double
    @AppStorage private var enabled: Bool
    init(reference: DailyIntakeReference, nutrition: NutritionValues) {
        self.reference = reference; self.nutrition = nutrition
        _value = AppStorage(wrappedValue: reference.defaultValue, reference.valueKey)
        _enabled = AppStorage(wrappedValue: true, reference.enabledKey)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !enabled {
                Text("Comparison off")
            } else if !reference.isValid(value) {
                Text("Set a valid daily value in Settings")
            } else {
                Text("\(value.formatted()) \(reference.nutrient.unit) · \(reference.label(for: value))")
                if let progress = DailyIntakeProgress(consumed: nutrition[reference.nutrient], target: value) {
                    let prefix = nutrition.estimated.contains(reference.nutrient) ? "~" : ""
                    ProgressView(value: progress.fraction).accessibilityHidden(true)
                    Text("\(prefix)\(progress.percentage.formatted(.number.precision(.fractionLength(0...1))))% · \(prefix)\(progress.status(for: reference))")
                        .accessibilityIdentifier("dailyProgress.\(reference.nutrient.rawValue)")
                } else {
                    Text("No visible data to compare")
                }
            }
        }
        .font(.caption).foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }
}
