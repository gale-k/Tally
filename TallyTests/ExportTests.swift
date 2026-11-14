import XCTest
import SwiftData
@testable import Tally

@MainActor
final class ExportTests: XCTestCase {
    func testJSONRoundTripPreservesTemplatesAndExcludesConsumption() throws {
        let original = SavedDrink(name: "Chai", brandOrLocation: "Fuel", volumeMl: 330, category: .teaChai,
                                  nutrition: .init(caffeine: 0, estimated: [.caffeine]), isFavourite: true, lastLoggedAt: .now, timesLogged: 9)
        let data = try DrinkExportService.export([original])
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertFalse(json.contains("timesLogged"))
        XCTAssertFalse(json.contains("lastLoggedAt"))
        let restored = try XCTUnwrap(DrinkExportService.decode(data).first).makeDrink()
        XCTAssertEqual(restored.id, original.id)
        XCTAssertEqual(restored.nutrition, original.nutrition)
        XCTAssertTrue(restored.isFavourite)
        XCTAssertEqual(restored.timesLogged, 0)
        XCTAssertNil(restored.caloriesKcal)
    }
    func testImportIsAdditiveAndIdempotent() throws {
        let container = try LibraryStore.container(configuration: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        let original = SavedDrink(name: "Coffee", nutrition: .init(caffeine: 100))
        let data = try DrinkExportService.export([original])
        let first = try DrinkExportService.importDrinks(data, into: container.mainContext)
        let second = try DrinkExportService.importDrinks(data, into: container.mainContext)
        XCTAssertEqual(first.imported, 1)
        XCTAssertEqual(second.imported, 0)
        XCTAssertEqual(second.skipped, 1)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<SavedDrink>()), 1)
    }
    func testRejectsMalformedVersionDuplicateIDsAndOversizedInput() throws {
        let drink = SavedDrink(name: "Coffee")
        let valid = try DrinkExportService.export([drink])
        XCTAssertThrowsError(try DrinkExportService.decode(Data("not json".utf8)))
        XCTAssertThrowsError(try DrinkExportService.decode(Data(repeating: 32, count: DrinkExportService.maximumBytes + 1)))
        var backup = SavedDrinkBackup(drinks: [SavedDrinkRecord(drink)])
        backup.version = 99
        XCTAssertThrowsError(try DrinkExportService.decode(encode(backup)))
        backup.version = 1; backup.drinks.append(backup.drinks[0])
        XCTAssertThrowsError(try DrinkExportService.decode(encode(backup)))
        XCTAssertEqual(try DrinkExportService.decode(valid).count, 1)
    }
    func testInvalidLaterRecordDoesNotPartiallyImport() throws {
        let container = try LibraryStore.container(configuration: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        var invalid = SavedDrinkRecord(SavedDrink(name: "Invalid"))
        invalid.nutrition.caffeine = -1
        let backup = SavedDrinkBackup(drinks: [SavedDrinkRecord(SavedDrink(name: "Valid")), invalid])
        XCTAssertThrowsError(try DrinkExportService.importDrinks(encode(backup), into: container.mainContext))
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<SavedDrink>()), 0)
    }
    func testEveryValidEditorTextCanBeExported() throws {
        var draft = DrinkDraft()
        draft.name = String(repeating: "Coffee ", count: 50)
        draft.brand = String(repeating: "Location ", count: 100)
        draft.notes = String(repeating: "A useful note. ", count: 1_000)
        let drink = try draft.makeDrink()
        let restored = try DrinkExportService.decode(DrinkExportService.export([drink]))
        XCTAssertEqual(restored.first?.name, drink.name)
        XCTAssertEqual(restored.first?.notes, drink.notes)
    }
    func testLiteralLegacyVersionOneFileStillImports() throws {
        // A fixed pre-theme export guards the original key names and raw values independently of today's encoder.
        let legacy = Data(#"""
        {"version":1,"drinks":[{"id":"4E93230F-C553-448F-82CE-8EE829BB0A53","name":"Legacy Coffee","brandOrLocation":"Fuel","size":"Iced","volumeMl":470,"category":"coffee","servingStyle":"iced","nutrition":{"caffeine":100,"estimated":["caffeine"]},"isFavourite":true,"createdAt":"2026-11-01T10:00:00Z","updatedAt":"2026-11-01T10:00:00Z"}]}
        """#.utf8)
        let container = try LibraryStore.container(configuration: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        XCTAssertEqual(try DrinkExportService.importDrinks(legacy, into: container.mainContext).imported, 1)
        let item = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<SavedDrink>()).first)
        XCTAssertEqual(item.category, .coffee)
        XCTAssertEqual(item.servingStyle, .iced)
        XCTAssertEqual(item.volumeMl, 470)
        XCTAssertEqual(item.nutrition.formatted(.caffeine), "~100 mg")
        XCTAssertTrue(item.isFavourite)
        XCTAssertNil(item.proteinG)
    }
    func testFoodCategoriesRoundTripWithoutChangingVersionOneKeys() throws {
        for category in [DrinkCategory.meal, .snack, .fruitVegetables, .dairyAlternatives] {
            let food = SavedDrink(name: "Food", category: category, nutrition: .init(calories: 250, protein: 18, estimated: [.protein]))
            let restored = try XCTUnwrap(DrinkExportService.decode(DrinkExportService.export([food])).first).makeDrink()
            XCTAssertEqual(restored.category, category)
            XCTAssertEqual(restored.servingStyle, .other)
            XCTAssertNil(restored.caffeineMg)
            XCTAssertEqual(restored.nutrition, food.nutrition)
        }
    }
    private func encode(_ backup: SavedDrinkBackup) throws -> Data {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(backup)
    }
}
