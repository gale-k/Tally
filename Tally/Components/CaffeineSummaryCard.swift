import SwiftUI

/// Caffeine shares the same comparison and optional-value behaviour as the other dashboard cards.
struct CaffeineSummaryCard: View {
    let nutrition: NutritionValues
    var fillRow = false
    var alignedStatusHeight: CGFloat?
    var body: some View { SecondaryNutritionCard(nutrient: .caffeine, nutrition: nutrition, fillRow: fillRow, alignedStatusHeight: alignedStatusHeight) }
}

/// The largest status reserves enough space for every card without truncating dynamic text.
struct NutritionStatusHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// The original visibility controls still govern these equal-weight dashboard cards.
struct SecondaryNutritionCard: View {
    let nutrient: Nutrient
    let nutrition: NutritionValues
    // Grid cards expand to their row's tallest neighbour; breakdown cards keep their natural height.
    var fillRow = false
    var alignedStatusHeight: CGFloat?
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(nutrient == .sugar ? "Total Sugars" : nutrient.title).font(.subheadline).foregroundStyle(.secondary)
            Text(nutrition.formatted(nutrient) ?? "— \(nutrient.unit)")
                .font(.title3.weight(.semibold)).monospacedDigit()
                .accessibilityLabel(amountLabel)
                .accessibilityIdentifier(nutrient == .caffeine ? "todayCaffeine" : "today.\(nutrient.rawValue)")
            if let reference = DailyIntakeReference.all.first(where: { $0.nutrient == nutrient }) {
                DailyIntakeComparison(reference: reference, nutrition: nutrition, alignedStatusHeight: alignedStatusHeight)
                    .frame(maxHeight: alignedStatusHeight == nil ? nil : .infinity, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: fillRow ? .infinity : nil, alignment: .topLeading).padding(16)
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
    let alignedStatusHeight: CGFloat?
    @AppStorage private var value: Double
    @AppStorage private var enabled: Bool
    init(reference: DailyIntakeReference, nutrition: NutritionValues, alignedStatusHeight: CGFloat? = nil) {
        self.reference = reference; self.nutrition = nutrition; self.alignedStatusHeight = alignedStatusHeight
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
                let progress = DailyIntakeProgress(consumed: nutrition[reference.nutrient], target: value)
                // Place each bar immediately below the amount so varying reference labels do not misalign rows.
                if let progress { ProgressView(value: progress.fraction).accessibilityHidden(true) }
                Text("\(value.formatted()) \(reference.nutrient.unit) · \(reference.label(for: value))")
                if reference.nutrient == .sodium { Text("Equivalent to \(reference.saltEquivalent(value))") }
                // Flexible space and measured status height align status text with its neighbour's.
                if alignedStatusHeight != nil { Spacer(minLength: 0) }
                if let progress {
                    let prefix = nutrition.estimated.contains(reference.nutrient) ? "~" : ""
                    Text("\(prefix)\(progress.percentage.formatted(.number.precision(.fractionLength(0...1))))% · \(prefix)\(progress.status(for: reference))")
                        .accessibilityIdentifier("dailyProgress.\(reference.nutrient.rawValue)")
                        .fixedSize(horizontal: false, vertical: true)
                        .background(GeometryReader { geometry in
                            Color.clear.preference(key: NutritionStatusHeightKey.self, value: alignedStatusHeight == nil ? 0 : geometry.size.height)
                        })
                        .frame(minHeight: alignedStatusHeight ?? 0, alignment: .topLeading)
                } else {
                    Text("No visible data to compare")
                        .fixedSize(horizontal: false, vertical: true)
                        .background(GeometryReader { geometry in
                            Color.clear.preference(key: NutritionStatusHeightKey.self, value: alignedStatusHeight == nil ? 0 : geometry.size.height)
                        })
                        .frame(minHeight: alignedStatusHeight ?? 0, alignment: .topLeading)
                }
            }
        }
        .font(.caption).foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: alignedStatusHeight == nil)
        .accessibilityElement(children: .combine)
    }
}
