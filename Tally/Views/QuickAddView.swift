import SwiftUI
import SwiftData

/// One-off drinks go directly to Health. A reusable template is an optional, separate local save after success.
struct QuickAddView: View {
    @Environment(HealthKitManager.self) private var health
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var draft = DrinkDraft()
    @State private var date = Date.now
    @State private var saveReusable = false
    @State private var saving = false
    @State private var savedToHealth = false
    @State private var error: String?

    var body: some View {
        Form {
            Section { TextField("Name (optional)", text: $draft.name).accessibilityIdentifier("quickDrinkName") }
            NutritionFormSection(draft: $draft)
            Section {
                DatePicker("Date & Time", selection: $date, in: ...Date.now)
                Toggle("Save as reusable drink", isOn: $saveReusable)
            } footer: { Text("Without a name, this will be called ‘Quick drink’. Unknown nutrition stays blank.") }
            Section {
                Button {
                    if savedToHealth { dismiss() } else { Task { await log() } }
                } label: {
                    HStack { Spacer(); if saving { ProgressView() }; Text(savedToHealth ? "Done" : "Log to Apple Health"); Spacer() }
                }
                .buttonStyle(.borderedProminent).listRowBackground(Color.clear).disabled(saving)
                .accessibilityIdentifier("quickLogToHealth")
            }
            if savedToHealth { Section { Label("Saved to Apple Health", systemImage: "checkmark.circle.fill").foregroundStyle(.green) } }
        }
        .disabled(saving || savedToHealth)
        .navigationTitle("Quick Add").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button(savedToHealth ? "Done" : "Cancel") { dismiss() }.disabled(saving) } }
        .interactiveDismissDisabled(saving)
        .errorAlert($error, title: savedToHealth ? "Saved, with a local update issue" : "Couldn’t log drink")
    }
    @MainActor private func log() async {
        guard !saving, !savedToHealth else { return }
        saving = true
        defer { saving = false }
        do {
            try draft.validate(requireName: false)
            let nutrition = try draft.nutrition()
            let name = DrinkDraft.optionalText(draft.name) ?? "Quick drink"
            try await health.log(.init(name: name, nutrition: nutrition, date: date))
            savedToHealth = true
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            if saveReusable {
                var reusable = draft
                reusable.name = name; reusable.category = .other; reusable.servingStyle = .other
                do {
                    let drink = try DrinkLibrary.save(reusable, in: context)
                    try DrinkLibrary.recordLog(for: drink, at: date, in: context)
                } catch {
                    self.error = "Your drink is saved in Apple Health. Tally couldn’t finish saving the reusable template. Don’t log it again. \(error.localizedDescription)"
                    return
                }
            }
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
