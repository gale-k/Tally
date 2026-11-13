import SwiftUI

/// Estimation is per value; blank input never acquires a numeric default.
struct NutritionField: View {
    let nutrient: Nutrient
    @Binding var text: String
    @Binding var estimated: Bool
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        // Larger text gets a full-width input line with its unit and estimate control alongside it.
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) { Text(nutrient.title); amountInput }
        } else {
            HStack { Text(nutrient.title); Spacer(minLength: 8); amountInput }
        }
    }
    private var amountInput: some View {
        HStack {
            TextField("Optional", text: $text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(minWidth: 55, maxWidth: typeSize.isAccessibilitySize ? .infinity : 115)
                .accessibilityLabel("\(nutrient.title), \(nutrient.unit)")
                .accessibilityIdentifier("nutrition.\(nutrient.rawValue)")
            Text(nutrient.unit).foregroundStyle(.secondary).font(.subheadline)
            Button { estimated.toggle() } label: {
                Text("~").font(.title3.weight(.semibold))
                    .frame(minWidth: 44, minHeight: 44)
                    .foregroundStyle(estimated ? Color.accentColor : .secondary)
                    .background(estimated ? Color.accentColor.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Estimate for \(nutrient.title)")
            .accessibilityValue(estimated ? "Estimated" : "Exact")
            .accessibilityIdentifier("estimate.\(nutrient.rawValue)")
        }
    }
}

/// Shared forms keep everyday food and drink values first, with extended values deliberately collapsed.
struct NutritionFormSection: View {
    @Binding var draft: DrinkDraft
    @State private var expanded = false
    var body: some View {
        Section {
            ForEach(Nutrient.formOrder.filter(\.isCore)) { field($0) }
            DisclosureGroup("More Nutrition", isExpanded: $expanded) {
                ForEach(Nutrient.formOrder.filter { !$0.isCore }) { field($0) }
            }
        } header: { Text("Nutrition per serving") }
        footer: { Text("Leave unknown values blank. Tap ~ to mark an estimate. Values are for one whole serving.") }
    }
    private func field(_ nutrient: Nutrient) -> some View {
        NutritionField(nutrient: nutrient,
                       text: Binding(get: { draft.values[nutrient] ?? "" }, set: { draft.values[nutrient] = $0 }),
                       estimated: Binding(get: { draft.estimated.contains(nutrient) }, set: { value in
                           if value { draft.estimated.insert(nutrient) } else { draft.estimated.remove(nutrient) }
                       }))
    }
}
