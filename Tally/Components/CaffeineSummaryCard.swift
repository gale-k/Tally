import SwiftUI

/// This target is a personal tracking preference, never presented as a medical limit.
struct CaffeineSummaryCard: View {
    let nutrition: NutritionValues
    let target: Double
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Caffeine Today").font(.headline)
                Spacer()
                Image(systemName: "cup.and.saucer.fill").foregroundStyle(.tint).accessibilityHidden(true)
            }
            Text(nutrition.formatted(.caffeine) ?? "— mg")
                .font(.system(.largeTitle, design: .rounded).weight(.semibold)).monospacedDigit()
                .accessibilityLabel(nutrition.caffeine == nil ? "No visible caffeine data today" : "Caffeine today, \(nutrition.formatted(.caffeine) ?? "")")
                .accessibilityIdentifier("todayCaffeine")
            if let caffeine = nutrition.caffeine {
                ProgressView(value: min(caffeine / target, 1))
                    .accessibilityLabel("Personal caffeine target")
                    .accessibilityValue("\(caffeine.formatted()) of \(target.formatted()) milligrams")
            } else { Capsule().fill(.quaternary).frame(height: 5).accessibilityHidden(true) }
            HStack {
                Text("\(target.formatted()) mg personal target")
                Spacer()
                if nutrition.estimated.contains(.caffeine) { Text("~ includes estimates") }
            }.font(.caption).foregroundStyle(.secondary)
        }
        .padding(20).background(.background, in: RoundedRectangle(cornerRadius: 24))
    }
}

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
        .background(.background, in: RoundedRectangle(cornerRadius: 20))
        .accessibilityElement(children: .combine)
    }
}
