import Foundation
import SwiftData

/// Small, explicit save boundaries keep SwiftData errors visible and prevent half-applied local edits.
@MainActor
enum DrinkLibrary {
    @discardableResult
    static func save(_ draft: DrinkDraft, editing drink: SavedDrink? = nil, in context: ModelContext) throws -> SavedDrink {
        do {
            let result: SavedDrink
            if let drink { try draft.apply(to: drink); result = drink }
            else { result = try draft.makeDrink(); context.insert(result) }
            try context.save()
            return result
        } catch { context.rollback(); throw error }
    }
    static func delete(_ drink: SavedDrink, in context: ModelContext) throws {
        // Intentionally no HealthKit call: removing a template never removes consumption history.
        do { context.delete(drink); try context.save() }
        catch { context.rollback(); throw error }
    }
    static func toggleFavourite(_ drink: SavedDrink, in context: ModelContext) throws {
        do { drink.isFavourite.toggle(); drink.updatedAt = .now; try context.save() }
        catch { context.rollback(); throw error }
    }
    @discardableResult
    static func duplicate(_ drink: SavedDrink, in context: ModelContext) throws -> SavedDrink {
        var draft = DrinkDraft(drink: drink)
        draft.name += " Copy"
        return try save(draft, in: context)
    }
    static func recordLog(for drink: SavedDrink, at date: Date, in context: ModelContext) throws {
        do {
            drink.lastLoggedAt = max(drink.lastLoggedAt ?? date, date)
            if drink.timesLogged < Int.max { drink.timesLogged += 1 }
            try context.save()
        } catch { context.rollback(); throw error }
    }
}

enum DrinkSort: String, CaseIterable, Identifiable {
    case recent, frequent, name, caffeineAscending, caffeineDescending
    var id: String { rawValue }
    var title: String {
        switch self {
        case .recent: "Recently Logged"
        case .frequent: "Most Logged"
        case .name: "Name"
        case .caffeineAscending: "Caffeine Low to High"
        case .caffeineDescending: "Caffeine High to Low"
        }
    }
}

/// Unknown caffeine sorts last in either direction rather than pretending it contains zero.
enum DrinkOrdering {
    static func sorted(_ drinks: [SavedDrink], by order: DrinkSort) -> [SavedDrink] {
        drinks.sorted { a, b in
            switch order {
            case .recent:
                if a.lastLoggedAt != b.lastLoggedAt { return (a.lastLoggedAt ?? .distantPast) > (b.lastLoggedAt ?? .distantPast) }
            case .frequent:
                if a.timesLogged != b.timesLogged { return a.timesLogged > b.timesLogged }
            case .caffeineAscending, .caffeineDescending:
                if a.caffeineMg != b.caffeineMg {
                    guard let left = a.caffeineMg else { return false }
                    guard let right = b.caffeineMg else { return true }
                    return order == .caffeineAscending ? left < right : left > right
                }
            case .name: break
            }
            let compared = a.name.localizedStandardCompare(b.name)
            return compared == .orderedSame ? a.id.uuidString < b.id.uuidString : compared == .orderedAscending
        }
    }
    static func quickLog(_ drinks: [SavedDrink]) -> [SavedDrink] {
        let sorted = drinks.sorted { a, b in
            if a.isFavourite != b.isFavourite { return a.isFavourite }
            if a.lastLoggedAt != b.lastLoggedAt { return (a.lastLoggedAt ?? .distantPast) > (b.lastLoggedAt ?? .distantPast) }
            if a.timesLogged != b.timesLogged { return a.timesLogged > b.timesLogged }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
        return Array(sorted.prefix(6))
    }
}
