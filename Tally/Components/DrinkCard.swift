import SwiftUI

/// A generous hit area and known nutrition make a usual item easy to find one-handed.
/// Secondary grouped surfaces preserve rounded-card separation in dark appearance.
struct DrinkCard: View {
    let drink: SavedDrink
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: drink.category.symbol).foregroundStyle(.tint)
                    Spacer()
                    if drink.isFavourite { Image(systemName: "star.fill").font(.caption).foregroundStyle(.tint) }
                }.accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    if let brand = drink.brandOrLocation { Text(brand).font(.caption).foregroundStyle(.secondary) }
                    Text(drink.name).font(.headline).foregroundStyle(.primary).lineLimit(2)
                }
                // A compact summary adapts to whichever nutrients are actually known.
                if drink.nutrition.isEmpty {
                    Text("Nutrition not added").font(.subheadline).foregroundStyle(.secondary)
                } else {
                    ForEach(drink.nutrition.summaryNutrients) { nutrient in
                        Text(drink.nutrition.summaryLabel(nutrient))
                            .font(.subheadline.weight(.medium)).foregroundStyle(.primary).monospacedDigit()
                    }
                }
                if let size = drink.size { Text(size).font(.caption).foregroundStyle(.secondary) }
            }
            .frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
            .contentShape(RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Review and confirm logging this item to Apple Health")
    }
}

struct DrinkRow: View {
    let drink: SavedDrink
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: drink.category.symbol)
                .font(.title3).foregroundStyle(.tint).frame(width: 42, height: 48)
                .background(Color.accentColor.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                if let brand = drink.brandOrLocation { Text(brand).font(.caption).foregroundStyle(.secondary) }
                Text(drink.name).font(.headline).foregroundStyle(.primary)
                if let size = drink.size { Text(size).font(.caption).foregroundStyle(.secondary) }
                if typeSize.isAccessibilitySize { NutritionSummaryView(nutrition: drink.nutrition, compact: true) }
            }
            Spacer(minLength: 6)
            if !typeSize.isAccessibilitySize { NutritionSummaryView(nutrition: drink.nutrition, compact: true) }
            if drink.isFavourite { Image(systemName: "star.fill").font(.caption).foregroundStyle(.tint).accessibilityLabel("Favourite") }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
