import SwiftUI

/// This target is a personal tracking preference, never presented as a medical limit.
/// Secondary grouped surfaces preserve rounded-card separation in dark appearance.
struct CaffeineSummaryCard: View {
    let nutrition: NutritionValues
    let target: Double
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Caffeine").font(.subheadline).foregroundStyle(.secondary)
            Text(nutrition.formatted(.caffeine) ?? "— mg")
                .font(.title3.weight(.semibold)).monospacedDigit()
                .accessibilityLabel(nutrition.caffeine == nil ? "No visible caffeine data today" : "Caffeine today, \(nutrition.formatted(.caffeine) ?? "")")
                .accessibilityIdentifier("todayCaffeine")
            if let caffeine = nutrition.caffeine {
                ProgressView(value: min(caffeine / target, 1))
                    .accessibilityLabel("Personal caffeine target")
                    .accessibilityValue("\(caffeine.formatted()) of \(target.formatted()) milligrams")
            }
            Text("\(target.formatted()) mg personal target").font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
    }
}

/// Equal visual weight keeps each chosen nutrient useful without assigning dietary goals.
struct SecondaryNutritionCard: View {
    let nutrient: Nutrient
    let nutrition: NutritionValues
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(nutrient.title).font(.subheadline).foregroundStyle(.secondary)
            Text(nutrition.formatted(nutrient) ?? "— \(nutrient.unit)").font(.title3.weight(.semibold)).monospacedDigit()
            Text("Apple Health · all sources").font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
        .accessibilityElement(children: .combine)
    }
}
