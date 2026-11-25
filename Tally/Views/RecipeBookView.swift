import SwiftUI
import SwiftData

/// The book reads recipes from their owning items so edits, archives and deletions are reflected automatically.
struct RecipeBookView: View {
    @Query(filter: #Predicate<SavedDrink> { $0.recipeIngredients != nil || $0.recipeMethod != nil }) private var recipes: [SavedDrink]
    @State private var search = ""

    var body: some View {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let matches = recipes.filter { recipe in
            query.isEmpty || recipe.name.localizedStandardContains(query) ||
                recipe.recipeIngredients?.localizedStandardContains(query) == true
        }
        List(DrinkOrdering.sorted(matches, by: .name)) { drink in
            // Use a direct destination within the Library's existing navigation stack.
            let id = drink.id
            NavigationLink { RecipeDetailView(id: id) } label: {
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(drink.name).font(.headline)
                        if drink.isArchived { Text("Archived").font(.caption).foregroundStyle(.secondary) }
                    }
                } icon: {
                    DrinkCategoryIcon(category: drink.category).foregroundStyle(.tint).accessibilityHidden(true)
                }
            }
            .accessibilityIdentifier("recipe.\(drink.name)")
        }
        .overlay {
            if recipes.isEmpty {
                ContentUnavailableView("No recipes yet", systemImage: "book",
                    description: Text("Turn on Homemade in a Library item, then tap Add Recipe."))
            } else if matches.isEmpty {
                ContentUnavailableView.search(text: search)
            }
        }
        .navigationTitle("Recipe Book")
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Name or ingredient")
    }
}

private struct RecipeDetailView: View {
    @Query private var items: [SavedDrink]
    @State private var sheet: DrinkSheet?

    init(id: UUID) {
        // Resolve the current item by ID so a remote edit or deletion is reflected on screen.
        _items = Query(filter: #Predicate<SavedDrink> { $0.id == id })
    }

    var body: some View {
        let drink = items.first
        List {
            if let ingredients = drink?.recipeIngredients {
                Section("Ingredients") { Text(ingredients).textSelection(.enabled) }
            }
            if let method = drink?.recipeMethod {
                Section("Method") { Text(method).textSelection(.enabled) }
            }
        }
        .overlay {
            if drink?.hasRecipe != true {
                ContentUnavailableView("Recipe unavailable", systemImage: "book.closed",
                    description: Text(drink == nil ? "The item was removed from your Library." : "Add ingredients or a method in Edit Item."))
            }
        }
        .navigationTitle(drink?.name ?? "Recipe")
        .toolbar {
            if let drink {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Edit Item", systemImage: "pencil") { sheet = .edit(drink) }
                        .accessibilityIdentifier("editRecipeItem")
                }
            }
        }
        .drinkSheets($sheet)
    }
}
