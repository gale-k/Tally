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
        let container = try ModelContainer(for: SavedDrink.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
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
        let container = try ModelContainer(for: SavedDrink.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        var invalid = SavedDrinkRecord(SavedDrink(name: "Invalid"))
        invalid.nutrition.caffeine = -1
        let backup = SavedDrinkBackup(drinks: [SavedDrinkRecord(SavedDrink(name: "Valid")), invalid])
        XCTAssertThrowsError(try DrinkExportService.importDrinks(encode(backup), into: container.mainContext))
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<SavedDrink>()), 0)
    }
    private func encode(_ backup: SavedDrinkBackup) throws -> Data {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(backup)
    }
}
