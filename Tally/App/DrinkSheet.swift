import SwiftUI

/// A single item-driven route prevents overlapping add, edit, and confirmation sheets.
enum DrinkSheet: Identifiable {
    case add, edit(SavedDrink), log(SavedDrink), quickAdd
    var id: String {
        switch self {
        case .add: "add"
        case let .edit(drink): "edit-\(drink.id)"
        case let .log(drink): "log-\(drink.id)"
        case .quickAdd: "quick"
        }
    }
}

extension View {
    func drinkSheets(_ route: Binding<DrinkSheet?>) -> some View {
        sheet(item: route) { destination in
            NavigationStack {
                switch destination {
                case .add: AddEditDrinkView()
                case let .edit(drink): AddEditDrinkView(drink: drink)
                case let .log(drink): LogDrinkSheet(drink: drink)
                case .quickAdd: QuickAddView()
                }
            }
        }
    }
}
