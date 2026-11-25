import SwiftUI
import SwiftData

/// Health is written once. If local usage counters fail afterwards, the UI explicitly prevents a duplicate retry.
struct LogDrinkSheet: View {
    @Environment(HealthKitManager.self) private var health
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    let drink: SavedDrink
    @State private var date = Date.now
    @State private var quantityText = "1"
    @State private var saving = false
    @State private var savedToHealth = false
    @State private var error: String?

    var body: some View {
        // Preview and save use the same snapshot of the original serving and the selected quantity.
        let snapshot = ServingQuantity.parse(quantityText, locale: locale).map(makeSnapshot)
        let canLog = snapshot.map { (try? $0.validate()) != nil } ?? false
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    if let brand = drink.brandOrLocation { Text(brand).font(.subheadline).foregroundStyle(.secondary) }
                    // Use the same category artwork as Library rows and Quick Log cards.
                    Label { Text(drink.name) } icon: { DrinkCategoryIcon(category: drink.category) }
                        .font(.title2.weight(.semibold))
                    if let size = drink.size, let amount = drink.servingAmount, size != amount.formatted(locale: locale) {
                        Text(size).foregroundStyle(.secondary)
                    }
                }.padding(.vertical, 8)
                ServingQuantitySelector(text: $quantityText, amount: drink.servingAmount, size: drink.size)
                    .disabled(saving || savedToHealth)
            }
            Section("Known nutrition") {
                if drink.nutrition.loggableNutrients.isEmpty {
                    if let nutrition = snapshot?.nutrition, !nutrition.isEmpty { NutritionSummaryView(nutrition: nutrition) }
                    Text("Add a nutrient amount greater than zero to this template before logging.").foregroundStyle(.secondary)
                } else if let snapshot {
                    if canLog { NutritionSummaryView(nutrition: snapshot.nutrition) }
                    else { Text("Choose a quantity that produces valid nutrition totals.").foregroundStyle(.secondary) }
                }
            }
            Section {
                DatePicker("Date & Time", selection: $date, in: ...Date.now).disabled(saving || savedToHealth)
            } footer: { Text("Apple Health skips zero amounts. ~ means estimated.") }
            Section {
                Button {
                    if savedToHealth { dismiss() }
                    else if let snapshot, canLog { Task { await log(snapshot) } }
                } label: {
                    HStack { Spacer(); if saving { ProgressView() }; Text(savedToHealth ? "Done" : "Log Item"); Spacer() }
                }
                .buttonStyle(.borderedProminent).foregroundStyle(Color(.systemBackground))
                .listRowBackground(Color.clear)
                .disabled(saving || (!savedToHealth && !canLog))
                .accessibilityIdentifier("confirmLogDrink")
            }
            if savedToHealth { Section { Label("Saved to Apple Health", systemImage: "checkmark.circle.fill").foregroundStyle(.green) } }
            if !health.isAvailable { Section { Text(HealthAccessError.unavailable.localizedDescription).foregroundStyle(.secondary) } }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Log Item").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button(savedToHealth ? "Done" : "Cancel") { dismiss() }.disabled(saving) } }
        .interactiveDismissDisabled(saving)
        .errorAlert($error, title: savedToHealth ? "Saved, with a local update issue" : "Couldn’t log item")
    }

    private func makeSnapshot(quantity: Double) -> ConsumptionDraft {
        ConsumptionDraft(name: drink.name, brand: drink.brandOrLocation, size: drink.size,
                         nutrition: drink.nutrition, date: date, quantity: quantity, servingAmount: drink.servingAmount)
    }

    @MainActor private func log(_ snapshot: ConsumptionDraft) async {
        guard !saving, !savedToHealth else { return }
        saving = true
        defer { saving = false }
        do {
            try await health.log(snapshot)
            savedToHealth = true
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            do { try DrinkLibrary.recordLog(for: drink, at: snapshot.date, in: context); dismiss() }
            catch { self.error = "Your entry is saved in Apple Health. Tally couldn’t update this template’s usage count. Don’t log it again. \(error.localizedDescription)" }
        } catch { self.error = error.localizedDescription }
    }
}
