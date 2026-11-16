import SwiftUI

/// Estimation is per value; blank input never acquires a numeric default.
struct NutritionField: View {
    let nutrient: Nutrient
    @Binding var text: String
    @Binding var estimated: Bool
    // Salt uses the shared numeric/estimate controls with its own visible label and unit.
    var inputTitle: String? = nil
    var inputUnit: String? = nil
    @Environment(\.dynamicTypeSize) private var typeSize
    private var title: String { inputTitle ?? nutrient.title }
    private var unit: String { inputUnit ?? nutrient.unit }

    var body: some View {
        // Larger text gets a full-width input line with its unit and estimate control alongside it.
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) { Text(title); amountInput }
        } else {
            HStack { Text(title); Spacer(minLength: 8); amountInput }
        }
    }
    private var amountInput: some View {
        HStack {
            TextField("Optional", text: $text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(minWidth: 55, maxWidth: typeSize.isAccessibilitySize ? .infinity : 115)
                .accessibilityLabel("\(title), \(unit)")
                .accessibilityIdentifier("nutrition.\(nutrient.rawValue)")
            Text(unit).foregroundStyle(.secondary).font(.subheadline)
            Button { estimated.toggle() } label: {
                Text("~").font(.title3.weight(.semibold))
                    .frame(minWidth: 44, minHeight: 44)
                    .foregroundStyle(estimated ? Color.accentColor : .secondary)
                    .background(estimated ? Color.accentColor.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Estimate for \(title)")
            .accessibilityValue(estimated ? "Estimated" : "Exact")
            .accessibilityIdentifier("estimate.\(nutrient.rawValue)")
        }
    }
}

/// Shared forms keep everyday food and drink values first, with extended values deliberately collapsed.
struct NutritionFormSection: View {
    @Binding var draft: DrinkDraft
    @State private var expanded = false
    @State private var error: String?
    var body: some View {
        Section {
            ForEach(Nutrient.formOrder.filter(\.isCore)) { field($0) }
            DisclosureGroup("More Nutrition", isExpanded: $expanded) {
                ForEach(Nutrient.formOrder.filter { !$0.isCore }) { nutrient in
                    if nutrient == .sodium {
                        // Switching units converts the existing input instead of silently reinterpreting it.
                        Picker("Sodium / Salt", selection: Binding(get: { draft.sodiumInputUnit }, set: { unit in
                            do { try draft.changeSodiumInputUnit(to: unit) }
                            catch { self.error = error.localizedDescription }
                        })) {
                            ForEach(SodiumInputUnit.allCases) { Text("\($0.title) (\($0.unit))").tag($0) }
                        }.pickerStyle(.menu).accessibilityIdentifier("sodiumInputUnit")
                        field(nutrient)
                        Text("Enter sodium or salt from the label. 1 g salt = 400 mg sodium. Saved to Apple Health as sodium.")
                            .font(.footnote).foregroundStyle(.secondary)
                    } else { field(nutrient) }
                }
            }
        } header: { Text("Nutrition per serving") }
        footer: { Text("Leave unknown values blank. Tap ~ to mark an estimate. Values are for one whole serving.") }
        .errorAlert($error, title: "Check sodium or salt")
    }
    private func field(_ nutrient: Nutrient) -> some View {
        NutritionField(nutrient: nutrient,
                       text: Binding(get: { draft.values[nutrient] ?? "" }, set: { draft.values[nutrient] = $0 }),
                       estimated: Binding(get: { draft.estimated.contains(nutrient) }, set: { value in
                           if value { draft.estimated.insert(nutrient) } else { draft.estimated.remove(nutrient) }
                       }),
                       inputTitle: nutrient == .sodium ? draft.sodiumInputUnit.title : nil,
                       inputUnit: nutrient == .sodium ? draft.sodiumInputUnit.unit : nil)
    }
}
