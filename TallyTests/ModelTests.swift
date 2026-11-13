import XCTest
import SwiftData
@testable import Tally

/// Pure model tests never request Health permissions or write health data.
final class ModelTests: XCTestCase {
    func testOptionalNutritionPreservesUnknownAndExplicitZero() throws {
        let values = NutritionValues(caffeine: 0)
        try values.validate()
        XCTAssertEqual(values.knownNutrients, [.caffeine])
        XCTAssertNil(values.calories)
        XCTAssertEqual(values.formatted(.caffeine), "0 mg")
    }
    func testRejectsNonfiniteNegativeAndUnreasonableValues() {
        for number in [-1, .infinity, .nan, 10_001] {
            XCTAssertThrowsError(try NutritionValues(caffeine: number).validate())
        }
    }
    func testEstimatedFormatting() {
        let values = NutritionValues(caffeine: 100, estimated: [.caffeine])
        XCTAssertEqual(values.formatted(.caffeine), "~100 mg")
    }
    func testDraftRequiresOnlyName() throws {
        var draft = DrinkDraft()
        XCTAssertThrowsError(try draft.validate())
        draft.name = "  My coffee  "
        let drink = try draft.makeDrink()
        XCTAssertEqual(drink.name, "My coffee")
        XCTAssertTrue(drink.nutrition.isEmpty)
        XCTAssertNil(drink.volumeMl)
    }
    func testDecimalParsingAndInvalidInput() throws {
        XCTAssertNil(try DrinkDraft.parse(" ", nutrient: .sugar))
        XCTAssertEqual(try DrinkDraft.parse("1,25", nutrient: .sugar, locale: Locale(identifier: "fr_FR")), 1.25)
        XCTAssertEqual(try DrinkDraft.parse("0", nutrient: .caffeine), 0)
        for invalid in ["nan", "inf", "-2", "1.2.3", "1,000", "1e300"] {
            XCTAssertThrowsError(try DrinkDraft.parse(invalid, nutrient: .caffeine, locale: Locale(identifier: "en_GB")))
        }
    }
    func testEditingTemplateDoesNotChangeSnapshot() throws {
        let drink = SavedDrink(name: "Mocha", nutrition: .init(caffeine: 100))
        let snapshot = drink.nutrition
        var draft = DrinkDraft(drink: drink)
        draft.values[.caffeine] = "110"
        try draft.apply(to: drink)
        XCTAssertEqual(snapshot.caffeine, 100)
        XCTAssertEqual(drink.caffeineMg, 110)
    }
    @MainActor
    func testSwiftDataRoundTrip() throws {
        let container = try ModelContainer(for: SavedDrink.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let drink = SavedDrink(name: "Latte", category: .coffee, servingStyle: .iced,
                               nutrition: .init(caffeine: 100, protein: 6, estimated: [.caffeine]))
        context.insert(drink)
        try context.save()
        let loaded = try context.fetch(FetchDescriptor<SavedDrink>()).first
        XCTAssertEqual(loaded?.nutrition, drink.nutrition)
        XCTAssertEqual(loaded?.servingStyle, .iced)
        XCTAssertNil(loaded?.caloriesKcal)
    }
}
