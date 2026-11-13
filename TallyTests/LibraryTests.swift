import XCTest
import SwiftData
@testable import Tally

@MainActor
final class LibraryTests: XCTestCase {
    func testCreateEditDuplicateDeleteAndUsage() throws {
        let container = try ModelContainer(for: SavedDrink.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        context.autosaveEnabled = false
        var draft = DrinkDraft()
        draft.name = "Mocha"; draft.values[.caffeine] = "100"
        let original = try DrinkLibrary.save(draft, in: context)
        try DrinkLibrary.recordLog(for: original, at: .now, in: context)
        try DrinkLibrary.toggleFavourite(original, in: context)
        XCTAssertEqual(original.timesLogged, 1)
        XCTAssertTrue(original.isFavourite)
        let copy = try DrinkLibrary.duplicate(original, in: context)
        XCTAssertNotEqual(copy.id, original.id)
        XCTAssertEqual(copy.caffeineMg, 100)
        XCTAssertEqual(copy.timesLogged, 0)
        XCTAssertNil(copy.lastLoggedAt)
        draft.values[.caffeine] = "110"
        try DrinkLibrary.save(draft, editing: original, in: context)
        XCTAssertEqual(copy.caffeineMg, 100)
        try DrinkLibrary.delete(original, in: context)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SavedDrink>()), 1)
    }
    func testUnknownCaffeineSortsLastAndQuickLogPrioritisesFavourite() {
        let unknown = SavedDrink(name: "Unknown")
        let zero = SavedDrink(name: "Chai", nutrition: .init(caffeine: 0), isFavourite: true)
        let coffee = SavedDrink(name: "Coffee", nutrition: .init(caffeine: 100), lastLoggedAt: .now, timesLogged: 4)
        XCTAssertEqual(DrinkOrdering.sorted([unknown, zero, coffee], by: .caffeineAscending).map(\.name), ["Chai", "Coffee", "Unknown"])
        XCTAssertEqual(DrinkOrdering.sorted([unknown, zero, coffee], by: .caffeineDescending).map(\.name), ["Coffee", "Chai", "Unknown"])
        XCTAssertEqual(DrinkOrdering.quickLog([unknown, zero, coffee]).first?.name, "Chai")
    }
    #if DEBUG
    func testDevelopmentExamplesNeverInventUnknownNutrition() throws {
        let container = try ModelContainer(for: SavedDrink.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        try DevelopmentData.seed(in: container.mainContext, defaults: nil)
        let drinks = try container.mainContext.fetch(FetchDescriptor<SavedDrink>())
        XCTAssertEqual(drinks.count, 6)
        XCTAssertTrue(drinks.filter { $0.category == .coffee }.allSatisfy { $0.caloriesKcal == nil && $0.sugarG == nil })
        let food = try XCTUnwrap(drinks.first { $0.name == "Lunch Bowl" })
        XCTAssertNil(food.caffeineMg)
        XCTAssertNil(food.volumeMl)
        XCTAssertEqual(food.servingStyle, .other)
        XCTAssertEqual(food.proteinG, 24)
        XCTAssertTrue(food.nutrition.estimated.contains(.protein))
        XCTAssertEqual(drinks.first { $0.name == "Iced Mocha" }?.volumeMl, 470)
        XCTAssertEqual(drinks.first { $0.brandOrLocation == "Starbucks" }?.caffeineMg, 125)
    }
    func testDevelopmentSeedKeepsExistingOnceOnlyMarker() throws {
        // Reusing the old marker prevents an app update from inserting a fresh batch into an existing library.
        let suite = "TallySeed-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let container = try ModelContainer(for: SavedDrink.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        defaults.set(true, forKey: "developmentPresetsSeeded.v1")
        try DevelopmentData.seed(in: container.mainContext, defaults: defaults)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<SavedDrink>()), 0)
        defaults.removeObject(forKey: DevelopmentData.marker)
        try DevelopmentData.seed(in: container.mainContext, defaults: defaults)
        try DevelopmentData.seed(in: container.mainContext, defaults: defaults)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<SavedDrink>()), 6)
    }
    #endif
}
