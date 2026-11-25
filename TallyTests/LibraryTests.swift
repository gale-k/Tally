import XCTest
import SwiftData
@testable import Tally

@MainActor
final class LibraryTests: XCTestCase {
    func testCreateEditDuplicateDeleteAndUsage() throws {
        let container = try LibraryStore.container(configuration: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        let context = container.mainContext
        context.autosaveEnabled = false
        var draft = DrinkDraft()
        draft.name = "Mocha"; draft.values[.caffeine] = "100"
        // Duplicating an item copies its recipe as independently editable text.
        draft.isHomemade = true
        draft.recipeIngredients = "Espresso\nMilk"
        draft.recipeMethod = "Stir together."
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
        XCTAssertTrue(copy.isHomemade)
        XCTAssertEqual(copy.recipeIngredients, "Espresso\nMilk")
        draft.values[.caffeine] = "110"
        draft.isHomemade = false
        draft.recipeMethod = " \n "
        try DrinkLibrary.save(draft, editing: original, in: context)
        XCTAssertFalse(original.isHomemade)
        XCTAssertTrue(original.hasRecipe)
        XCTAssertNil(original.recipeMethod)
        XCTAssertEqual(copy.recipeMethod, "Stir together.")
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
    /// Archived favourites cannot occupy any of the six slots, and toggles preserve the template and usage.
    func testArchiveFiltersQuickLogAndPreservesDetails() throws {
        let container = try LibraryStore.container(configuration: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        let context = container.mainContext
        context.autosaveEnabled = false
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let item = SavedDrink(name: "Favourite", weightG: 42, nutrition: .init(protein: 5, estimated: [.protein]), notes: "Note", isFavourite: true, lastLoggedAt: date, timesLogged: 7)
        context.insert(item); try context.save()
        let id = item.id
        try DrinkLibrary.setArchived(true, for: item, in: context)
        let active = (0..<7).map { SavedDrink(name: "Active \($0)") }
        XCTAssertEqual(DrinkOrdering.quickLog([item] + active).count, 6)
        XCTAssertFalse(DrinkOrdering.quickLog([item] + active).contains { $0.id == id })
        XCTAssertEqual(item.weightG, 42); XCTAssertEqual(item.notes, "Note")
        XCTAssertEqual(item.nutrition.estimated, [.protein]); XCTAssertTrue(item.isFavourite)
        XCTAssertEqual(item.lastLoggedAt, date); XCTAssertEqual(item.timesLogged, 7)
        let staged = try XCTUnwrap(LibrarySyncStore.state(for: id, in: context))
        XCTAssertFalse(staged.tombstone); XCTAssertEqual(try LibrarySyncStore.change(staged).template?.isArchived, true)
        try DrinkLibrary.setArchived(false, for: item, in: context)
        XCTAssertEqual(DrinkOrdering.quickLog([item] + active).first?.id, id)
        XCTAssertFalse(item.isArchived)
    }

    /// A failed staging validation rolls the attempted archive edit back along with the outbox.
    func testArchiveFailureRollsBack() throws {
        let container = try LibraryStore.container(configuration: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        let context = container.mainContext; context.autosaveEnabled = false
        let item = SavedDrink(name: "Invalid", nutrition: .init(caffeine: -1))
        context.insert(item); try context.save()
        XCTAssertThrowsError(try DrinkLibrary.setArchived(true, for: item, in: context))
        XCTAssertFalse(item.isArchived)
        XCTAssertNil(try LibrarySyncStore.state(for: item.id, in: context))
    }

    /// Archive state and the recipe survive reopening the actual on-disk store.
    func testArchivedRecipeSurvivesStoreReopen() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("TallyArchive-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let configuration = ModelConfiguration(url: folder.appendingPathComponent("Library.store"), cloudKitDatabase: .none)
        do {
            let container = try LibraryStore.container(configuration: configuration)
            var draft = DrinkDraft()
            draft.name = "Saved"; draft.isHomemade = true
            draft.recipeIngredients = "  80 g oats\n150 ml milk  \n"
            let item = try DrinkLibrary.save(draft, in: container.mainContext)
            try DrinkLibrary.setArchived(true, for: item, in: container.mainContext)
        }
        let reopened = try LibraryStore.container(configuration: configuration)
        let item = try XCTUnwrap(reopened.mainContext.fetch(FetchDescriptor<SavedDrink>()).first)
        XCTAssertTrue(item.isArchived)
        XCTAssertTrue(item.isHomemade)
        XCTAssertTrue(item.hasRecipe)
        XCTAssertEqual(item.recipeIngredients, "80 g oats\n150 ml milk")
        XCTAssertNil(item.recipeMethod)
    }
    #if DEBUG
    func testDevelopmentExamplesNeverInventUnknownNutrition() throws {
        let container = try LibraryStore.container(configuration: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
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
        let container = try LibraryStore.container(configuration: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
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
