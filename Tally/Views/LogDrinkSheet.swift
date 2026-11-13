import SwiftUI
import SwiftData

/// Health is written once. If local usage counters fail afterwards, the UI explicitly prevents a duplicate retry.
struct LogDrinkSheet: View {
    @Environment(HealthKitManager.self) private var health
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let drink: SavedDrink
    @State private var date = Date.now
    @State private var saving = false
    @State private var savedToHealth = false
    @State private var error: String?

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    if let brand = drink.brandOrLocation { Text(brand).font(.subheadline).foregroundStyle(.secondary) }
                    Label(drink.name, systemImage: drink.category.symbol).font(.title2.weight(.semibold))
                    if let size = drink.size { Text(size).foregroundStyle(.secondary) }
                }.padding(.vertical, 8)
            }
            Section("Known nutrition") {
                if drink.nutrition.isEmpty { Text("Add at least one nutrition value to this template before logging.").foregroundStyle(.secondary) }
                else { NutritionSummaryView(nutrition: drink.nutrition) }
            }
            Section {
                DatePicker("Date & Time", selection: $date, in: ...Date.now).disabled(saving || savedToHealth)
            } footer: { Text("Only the values shown above will be saved. ~ means estimated.") }
            Section {
                Button {
                    if savedToHealth { dismiss() } else { Task { await log() } }
                } label: {
                    HStack { Spacer(); if saving { ProgressView() }; Text(savedToHealth ? "Done" : "Log Item"); Spacer() }
                }
                .buttonStyle(.borderedProminent).foregroundStyle(Color(.systemBackground))
                .listRowBackground(Color.clear)
                .disabled(saving || (!savedToHealth && drink.nutrition.isEmpty))
                .accessibilityIdentifier("confirmLogDrink")
            }
            if savedToHealth { Section { Label("Saved to Apple Health", systemImage: "checkmark.circle.fill").foregroundStyle(.green) } }
            if !health.isAvailable { Section { Text(HealthAccessError.unavailable.localizedDescription).foregroundStyle(.secondary) } }
        }
        .navigationTitle("Log Item").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button(savedToHealth ? "Done" : "Cancel") { dismiss() }.disabled(saving) } }
        .interactiveDismissDisabled(saving)
        .errorAlert($error, title: savedToHealth ? "Saved, with a local update issue" : "Couldn’t log item")
    }
    @MainActor private func log() async {
        guard !saving, !savedToHealth else { return }
        saving = true
        defer { saving = false }
        do {
            let snapshot = ConsumptionDraft(name: drink.name, brand: drink.brandOrLocation, size: drink.size, nutrition: drink.nutrition, date: date)
            try await health.log(snapshot)
            savedToHealth = true
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            do { try DrinkLibrary.recordLog(for: drink, at: date, in: context); dismiss() }
            catch { self.error = "Your entry is saved in Apple Health. Tally couldn’t update this template’s usage count. Don’t log it again. \(error.localizedDescription)" }
        } catch { self.error = error.localizedDescription }
    }
}
