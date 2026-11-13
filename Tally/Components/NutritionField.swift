import SwiftUI

/// Estimation is per value; blank input never acquires a numeric default.
struct NutritionField: View {
    let nutrient: Nutrient
    @Binding var text: String
    @Binding var estimated: Bool

    var body: some View {
        HStack {
            Text(nutrient.title)
            Spacer(minLength: 8)
            TextField("Optional", text: $text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(minWidth: 55, maxWidth: 115)
                .accessibilityLabel("\(nutrient.title), \(nutrient.unit)")
                .accessibilityIdentifier("nutrition.\(nutrient.rawValue)")
            Text(nutrient.unit).foregroundStyle(.secondary).font(.subheadline)
            Button { estimated.toggle() } label: {
                Text("~").font(.title3.weight(.semibold))
                    .frame(width: 36, height: 44)
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

/// Shared forms keep caffeine, calories, and sugar first, with extended values deliberately collapsed.
struct NutritionFormSection: View {
    @Binding var draft: DrinkDraft
    @State private var expanded = false
    var body: some View {
        Section {
            ForEach(Nutrient.allCases.filter(\.isCore)) { field($0) }
            DisclosureGroup("More Nutrition", isExpanded: $expanded) {
                ForEach(Nutrient.allCases.filter { !$0.isCore }) { field($0) }
            }
        } header: { Text("Nutrition per drink") }
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
