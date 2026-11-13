import SwiftUI
import SwiftData

/// The draft is applied only when Save succeeds; dismissing the form preserves the original template.
struct AddEditDrinkView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    private let drink: SavedDrink?
    @State private var draft: DrinkDraft
    @State private var error: String?

    init(drink: SavedDrink? = nil) {
        self.drink = drink
        _draft = State(initialValue: drink.map(DrinkDraft.init(drink:)) ?? DrinkDraft())
    }
    var body: some View {
        Form {
            Section("The basics") {
                TextField("Drink Name", text: $draft.name).textInputAutocapitalization(.words).accessibilityIdentifier("drinkName")
                TextField("Brand / Location", text: $draft.brand).textInputAutocapitalization(.words)
                TextField("Size", text: $draft.size)
                HStack {
                    Text("Volume")
                    TextField("Optional", text: $draft.volume).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                        .accessibilityLabel("Volume, millilitres")
                    Text("ml").foregroundStyle(.secondary)
                }
                Picker("Category", selection: $draft.category) {
                    ForEach(DrinkCategory.allCases) { Text($0.title).tag($0) }
                }
                Picker("Serving Style", selection: $draft.servingStyle) {
                    ForEach(ServingStyle.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Favourite", isOn: $draft.isFavourite)
            }
            NutritionFormSection(draft: $draft)
            Section("Notes") { TextField("Anything worth remembering", text: $draft.notes, axis: .vertical).lineLimit(3...6) }
            Section { Text("This is a reusable template. Editing it won’t change anything already logged to Apple Health.").font(.footnote).foregroundStyle(.secondary) }
        }
        // Native interactive dismissal avoids a flexible custom keyboard-accessory layout during focus changes.
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(drink == nil ? "Add Drink" : "Edit Drink")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    do { try DrinkLibrary.save(draft, editing: drink, in: context); dismiss() }
                    catch { self.error = error.localizedDescription }
                }.fontWeight(.semibold).accessibilityIdentifier("saveDrink")
            }
        }
        .errorAlert($error, title: "Couldn’t save drink")
    }
}
