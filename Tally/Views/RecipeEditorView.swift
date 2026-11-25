import SwiftUI

/// Done copies the recipe into the item draft. Cancel or swipe to dismiss discards this sheet's edits.
struct RecipeEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding private var itemIngredients: String
    @Binding private var itemMethod: String
    @State private var ingredients: String
    @State private var method: String

    init(ingredients: Binding<String>, method: Binding<String>) {
        _itemIngredients = ingredients
        _itemMethod = method
        _ingredients = State(initialValue: ingredients.wrappedValue)
        _method = State(initialValue: method.wrappedValue)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Ingredients") {
                    TextField("Ingredients", text: $ingredients, prompt: Text("List ingredients and quantities"), axis: .vertical)
                        .lineLimit(3...12).accessibilityLabel("Ingredients").accessibilityIdentifier("recipeIngredients")
                }
                Section("Method") {
                    TextField("Method", text: $method, prompt: Text("Write the steps"), axis: .vertical)
                        .lineLimit(3...12).accessibilityLabel("Method").accessibilityIdentifier("recipeMethod")
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Recipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        itemIngredients = ingredients
                        itemMethod = method
                        dismiss()
                    }.accessibilityIdentifier("doneRecipe")
                }
            }
        }
        #if DEBUG
        // The modal root applies the same screenshot fixture overrides as the item editor.
        .modifier(DevelopmentAppearance())
        #endif
    }
}
