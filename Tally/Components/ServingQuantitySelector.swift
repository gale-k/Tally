import SwiftUI

/// The same field drives the live preview for logging and for editing a history entry.
struct ServingQuantitySelector: View {
    @Binding var text: String
    var amount: ServingAmount? = nil
    var size: String? = nil
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var typeSize
    @FocusState private var editing: Bool

    private var quantity: Double? { ServingQuantity.parse(text, locale: locale) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) { Text("Servings"); controls }
            } else {
                HStack { Text("Servings"); Spacer(minLength: 8); controls }
            }
            if let amount {
                let perServing = amount.formatted(locale: locale)
                if let quantity, quantity != 1, ServingQuantity.isValid(amount.value * quantity) {
                    let total = amount.formatted(quantity: quantity, locale: locale)
                    Text("\(perServing) per serving · \(total) total")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .accessibilityIdentifier("totalServingSize")
                } else {
                    Text("\(perServing) per serving").font(.subheadline).foregroundStyle(.secondary)
                }
            } else if let size {
                Text("Serving size · \(size)").font(.subheadline).foregroundStyle(.secondary)
            }
            if quantity == nil {
                Text("Enter a serving quantity greater than zero.").font(.footnote).foregroundStyle(.secondary)
            }
            if editing {
                // The decimal pad has no return key. Keep dismissal available on the form while editing.
                Button("Done") { editing = false }
                    .buttonStyle(.borderless)
                    .frame(minHeight: 44)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .accessibilityIdentifier("finishServingQuantityEditing")
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 2) {
            stepButton("Decrease quantity", image: "minus", identifier: "decreaseServingQuantity", value: decreasedQuantity)
            TextField("Quantity", text: $text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.center)
                .monospacedDigit()
                .focused($editing)
                .onSubmit { editing = false }
                .frame(minWidth: 56, idealWidth: 72, maxWidth: typeSize.isAccessibilitySize ? .infinity : 84, minHeight: 44)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                .accessibilityLabel("Serving quantity")
                .accessibilityIdentifier("servingQuantity")
            stepButton("Increase quantity", image: "plus", identifier: "increaseServingQuantity", value: increasedQuantity)
        }
    }

    // Whole-serving taps keep repeat logging quick, with a half serving one tap below one.
    private var decreasedQuantity: Double? {
        guard let quantity, quantity > 0.5 else { return nil }
        let decreased = quantity > 1 ? stepped(quantity, by: -1) : 0.5
        return decreased < quantity && ServingQuantity.isValid(decreased) ? decreased : nil
    }

    private var increasedQuantity: Double? {
        guard let quantity else { return nil }
        let increased = stepped(quantity, by: 1)
        return increased > quantity && ServingQuantity.isValid(increased) ? increased : nil
    }

    private func stepped(_ quantity: Double, by step: Int) -> Double {
        // Use the shortest decimal round-trip for typed fractions, so 1.2 − 1 displays as 0.2.
        let decimal = Decimal(string: String(quantity), locale: Locale(identifier: "en_US_POSIX"))
        if let decimal, let result = Double((decimal + Decimal(step)).description), result.isFinite {
            return result
        }
        // Quantities beyond Decimal's exponent range can still be valid Double input.
        return quantity + Double(step)
    }

    private func stepButton(_ label: String, image: String, identifier: String, value: Double?) -> some View {
        Button {
            if let value { text = ServingQuantity.formatted(value, locale: locale) }
        } label: {
            Image(systemName: image).frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .disabled(value == nil)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }
}
