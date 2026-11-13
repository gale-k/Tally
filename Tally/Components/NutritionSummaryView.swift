import SwiftUI

/// Optional summaries retain estimate markers and never fill absent nutrients with zero.
struct NutritionSummaryView: View {
    let nutrition: NutritionValues
    var compact = false
    var body: some View {
        if compact {
            VStack(alignment: .trailing, spacing: 4) {
                if nutrition.isEmpty {
                    Text("Nutrition not added").font(.subheadline).foregroundStyle(.secondary)
                } else {
                    ForEach(nutrition.summaryNutrients) { nutrient in
                        Text(nutrition.summaryLabel(nutrient))
                            .font(nutrient == nutrition.summaryNutrients.first ? .subheadline.weight(.semibold) : .caption)
                            .foregroundStyle(nutrient == nutrition.summaryNutrients.first ? .primary : .secondary)
                    }
                }
            }.monospacedDigit()
        } else {
            ForEach(nutrition.displayNutrients) { nutrient in
                LabeledContent(nutrient.title, value: nutrition.formatted(nutrient) ?? "")
                    .accessibilityLabel("\(nutrient.title), \(nutrition.formatted(nutrient) ?? "")\(nutrition.estimated.contains(nutrient) ? ", estimated" : "")")
            }
        }
    }
}

extension View {
    /// All recoverable failures have a visible explanation rather than a console-only print.
    func errorAlert(_ message: Binding<String?>, title: String = "Something needs attention") -> some View {
        alert(title, isPresented: Binding(get: { message.wrappedValue != nil }, set: { if !$0 { message.wrappedValue = nil } })) {
            Button("OK", role: .cancel) { message.wrappedValue = nil }
        } message: { Text(message.wrappedValue ?? "") }
    }
}
