import SwiftUI
import SwiftData

/// The library is purely local. Row taps always open confirmation before any health write.
struct DrinksView: View {
    @Environment(\.modelContext) private var context
    @Query private var drinks: [SavedDrink]
    @State private var search = ""
    @State private var category: DrinkCategory?
    @State private var favouritesOnly = false
    @State private var sort: DrinkSort = .recent
    @State private var sheet: DrinkSheet?
    @State private var deleting: SavedDrink?
    @State private var error: String?

    private var filtered: [SavedDrink] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return DrinkOrdering.sorted(drinks.filter { drink in
            (category == nil || category == drink.category) && (!favouritesOnly || drink.isFavourite) &&
            (query.isEmpty || [drink.name, drink.brandOrLocation ?? "", drink.size ?? ""].contains { $0.localizedStandardContains(query) })
        }, by: sort)
    }

    var body: some View {
        List {
            Section {
                HStack {
                    Menu {
                        Picker("Category", selection: $category) {
                            Text("All Categories").tag(nil as DrinkCategory?)
                            ForEach(DrinkCategory.allCases) { Text($0.title).tag(Optional($0)) }
                        }
                    } label: { Label(category?.title ?? "All Drinks", systemImage: "line.3.horizontal.decrease") }
                    Spacer()
                    Button { favouritesOnly.toggle() } label: { Image(systemName: favouritesOnly ? "star.fill" : "star") }
                        .accessibilityLabel("Favourites only").accessibilityValue(favouritesOnly ? "On" : "Off")
                    Menu {
                        Picker("Sort drinks", selection: $sort) { ForEach(DrinkSort.allCases) { Text($0.title).tag($0) } }
                    } label: { Image(systemName: "arrow.up.arrow.down") }.accessibilityLabel("Sort drinks")
                }.buttonStyle(.borderless)
            }
            Section {
                ForEach(filtered) { drink in
                    HStack(spacing: 4) {
                        Button { sheet = .log(drink) } label: { DrinkRow(drink: drink) }.buttonStyle(.plain)
                            .accessibilityIdentifier("drink.\(drink.name)")
                        Menu {
                            Button("Log Drink", systemImage: "plus.circle") { sheet = .log(drink) }
                            Button("Edit Drink", systemImage: "pencil") { sheet = .edit(drink) }
                            Button(drink.isFavourite ? "Unfavourite" : "Favourite", systemImage: "star") {
                                perform { try DrinkLibrary.toggleFavourite(drink, in: context) }
                            }
                            Button("Duplicate", systemImage: "plus.square.on.square") {
                                perform { try DrinkLibrary.duplicate(drink, in: context) }
                            }
                            Button("Delete Drink", systemImage: "trash", role: .destructive) { deleting = drink }
                        } label: { Image(systemName: "ellipsis").frame(width: 36, height: 48).contentShape(Rectangle()) }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("More actions for \(drink.name)")
                    }
                }
            } header: {
                if !filtered.isEmpty { Text("\(filtered.count) \(filtered.count == 1 ? "drink" : "drinks") · tap to log") }
            }
            if filtered.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label(drinks.isEmpty ? "Meet your usuals" : "No matching drinks", systemImage: "cup.and.saucer")
                    } description: {
                        Text(drinks.isEmpty ? "Save your favourite coffee, can, or cup once. Next time, it’s a couple of taps." : "Try another search or change your filters.")
                    } actions: {
                        if drinks.isEmpty { Button("Add Your First Drink") { sheet = .add }.buttonStyle(.borderedProminent) }
                    }.listRowBackground(Color.clear)
                }
            }
        }
        .searchable(text: $search, prompt: "Name, brand, or size")
        .navigationTitle("Drinks")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("Quick Add", systemImage: "bolt.badge.plus") { sheet = .quickAdd }
                Button("Add Drink", systemImage: "plus") { sheet = .add }.accessibilityIdentifier("addDrink")
            }
        }
        .drinkSheets($sheet)
        .confirmationDialog("Delete this saved drink?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("Delete Drink", role: .destructive) {
                if let deleting { perform { try DrinkLibrary.delete(deleting, in: context) } }
                deleting = nil
            }
        } message: { Text("Nutrition already saved to Apple Health will stay there.") }
        .errorAlert($error)
    }
    private func perform<T>(_ action: () throws -> T) {
        do { _ = try action() } catch { self.error = error.localizedDescription }
    }
}
