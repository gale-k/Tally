import SwiftUI
import SwiftData

/// The library is purely local. Row taps always open confirmation before any health write.
struct DrinksView: View {
    @Environment(\.modelContext) private var context
    @Query private var drinks: [SavedDrink]
    @State private var search = ""
    @State private var category: DrinkCategory?
    @State private var favouritesOnly = false
    @State private var showingArchive = false
    @State private var sort: DrinkSort = .recent
    @State private var sheet: DrinkSheet?
    @State private var deleting: SavedDrink?
    @State private var error: String?

    private var filtered: [SavedDrink] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return DrinkOrdering.sorted(drinks.filter { drink in
            drink.isArchived == showingArchive && (category == nil || category == drink.category) && (!favouritesOnly || drink.isFavourite) &&
            (query.isEmpty || [drink.name, drink.brandOrLocation ?? "", drink.size ?? ""].contains { $0.localizedStandardContains(query) })
        }, by: sort)
    }

    var body: some View {
        List {
            // Recipe Book has its own search and includes recipes from both Library scopes.
            Section {
                NavigationLink { RecipeBookView() } label: { Label("Recipe Book", systemImage: "book") }
                    .accessibilityIdentifier("openRecipeBook")
            }
            // Keep the archive accessible alongside the same search, filter and sort controls.
            Section {
                Picker("Library items", selection: $showingArchive) {
                    Text("Active").tag(false)
                    Text("Archived").tag(true)
                }.pickerStyle(.segmented).accessibilityIdentifier("libraryScope")
            }
            Section {
                HStack {
                    Menu {
                        Picker("Category", selection: $category) {
                            Text("All Categories").tag(nil as DrinkCategory?)
                            ForEach(DrinkCategory.allCases) { Text($0.title).tag(Optional($0)) }
                        }
                    } label: { Label(category?.title ?? "All Items", systemImage: "line.3.horizontal.decrease") }
                    Spacer()
                    Button { favouritesOnly.toggle() } label: { Image(systemName: favouritesOnly ? "star.fill" : "star") }
                        .accessibilityLabel("Favourites only").accessibilityValue(favouritesOnly ? "On" : "Off")
                    Menu {
                        Picker("Sort items", selection: $sort) { ForEach(DrinkSort.allCases) { Text($0.title).tag($0) } }
                    } label: { Image(systemName: "arrow.up.arrow.down") }.accessibilityLabel("Sort items")
                }.buttonStyle(.borderless)
            }
            Section {
                ForEach(filtered) { drink in
                    HStack(spacing: 4) {
                        Button { sheet = showingArchive ? .edit(drink) : .log(drink) } label: { DrinkRow(drink: drink) }.buttonStyle(.plain)
                            .accessibilityIdentifier("drink.\(drink.name)")
                        Menu {
                            if !showingArchive { Button("Log Item", systemImage: "plus.circle") { sheet = .log(drink) } }
                            Button("Edit Item", systemImage: "pencil") { sheet = .edit(drink) }
                            Button(drink.isFavourite ? "Unfavourite" : "Favourite", systemImage: "star") {
                                perform { try DrinkLibrary.toggleFavourite(drink, in: context) }
                            }
                            Button("Duplicate", systemImage: "plus.square.on.square") {
                                perform { try DrinkLibrary.duplicate(drink, in: context) }
                            }
                            Button(drink.isArchived ? "Unarchive Item" : "Archive Item", systemImage: drink.isArchived ? "archivebox" : "archivebox.fill") {
                                perform { try DrinkLibrary.setArchived(!drink.isArchived, for: drink, in: context) }
                            }
                            Button("Delete Item", systemImage: "trash", role: .destructive) { deleting = drink }
                        } label: { Image(systemName: "ellipsis").frame(width: 36, height: 48).contentShape(Rectangle()) }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("More actions for \(drink.name)")
                    }
                }
            } header: {
                if !filtered.isEmpty { Text("\(filtered.count) \(filtered.count == 1 ? "item" : "items") · \(showingArchive ? "tap to edit" : "tap to log")") }
            }
            if filtered.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label(emptyTitle, systemImage: showingArchive ? "archivebox" : "list.bullet.clipboard")
                    } description: {
                        Text(emptyDescription)
                    } actions: {
                        if drinks.isEmpty && !showingArchive { Button("Add Your First Item") { sheet = .add }.buttonStyle(.borderedProminent).foregroundStyle(Color(.systemBackground)) }
                    }.listRowBackground(Color.clear)
                }
            }
        }
        // Keep the native search field visible so finding a saved drink does not require discovering a pull gesture.
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Name, brand, or size")
        .navigationTitle("Library")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("Quick Add", systemImage: "plus.circle") { sheet = .quickAdd }
                Button("Add Item", systemImage: "plus") { sheet = .add }.accessibilityIdentifier("addDrink")
            }
        }
        .drinkSheets($sheet)
        .confirmationDialog("Delete this saved item?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible, presenting: deleting) { item in
            Button("Delete Item", role: .destructive) {
                // Capture the presented item: dismissal can clear the selection before this action executes.
                perform { try DrinkLibrary.delete(item, in: context) }
                deleting = nil
            }
        } message: { item in
            if item.hasRecipe { Text("This also deletes its recipe from Recipe Book. Nutrition already saved to Apple Health will stay there.") }
            else { Text("Nutrition already saved to Apple Health will stay there.") }
        }
        .errorAlert($error)
    }
    // Distinguish an empty collection from filters hiding otherwise available items.
    private var emptyTitle: String {
        if drinks.contains(where: { $0.isArchived == showingArchive }) { return "No matching items" }
        if showingArchive { return "No archived items" }
        return drinks.isEmpty ? "Meet your usuals" : "No active items"
    }
    private var emptyDescription: String {
        if drinks.contains(where: { $0.isArchived == showingArchive }) { return "Try another search or change your filters." }
        if showingArchive { return "Archived items appear here, ready to edit or restore." }
        return drinks.isEmpty ? "Save the foods and drinks you return to. Next time, logging takes a couple of taps." : "Restore an item from Archived or add a new one."
    }
    private func perform<T>(_ action: () throws -> T) {
        do { _ = try action() } catch { self.error = error.localizedDescription }
    }
}
