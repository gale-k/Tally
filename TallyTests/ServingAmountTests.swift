import XCTest
import SwiftData
import UIKit
@testable import Tally

/// Serving amounts remain template metadata, independently of the item's nutrition.
@MainActor
final class ServingAmountTests: XCTestCase {
    func testUnitSwitchClearsPreviousMeasurementAndPreservesNutrition() throws {
        let item = SavedDrink(name: "Chocolate", volumeMl: 45, nutrition: .init(calories: 240))
        var draft = DrinkDraft(drink: item)
        XCTAssertEqual(draft.amountUnit, .millilitres)
        XCTAssertEqual(try draft.validatedAmount(), 45)
        draft.amountUnit = .grams; draft.servingStyle = .cold; draft.category = .snack
        try draft.apply(to: item)
        XCTAssertNil(item.volumeMl)
        XCTAssertEqual(item.weightG, 45)
        XCTAssertEqual(item.caloriesKcal, 240)
        let reopened = DrinkDraft(drink: item)
        XCTAssertEqual(reopened.amountUnit, .grams)
        XCTAssertEqual(reopened.servingStyle, .cold)
        XCTAssertEqual(try reopened.validatedAmount(), 45)
        draft.amountUnit = .millilitres
        try draft.apply(to: item)
        XCTAssertNil(item.weightG)
        XCTAssertEqual(item.volumeMl, 45)
        XCTAssertEqual(item.caloriesKcal, 240)
    }

    func testOptionalAmountsAndValidationUseSelectedUnit() throws {
        for unit in ServingAmountUnit.allCases {
            var draft = DrinkDraft(); draft.name = "Item"; draft.amountUnit = unit
            XCTAssertNil(try draft.validatedAmount())
            draft.amount = "100000"
            XCTAssertEqual(try draft.validatedAmount(), 100_000)
            for invalid in ["0", "-1", "nan", "inf", "100001", "oops"] {
                draft.amount = invalid
                XCTAssertThrowsError(try draft.makeDrink()) { error in
                    XCTAssertTrue(error.localizedDescription.contains(unit.rawValue))
                }
            }
        }
    }

    func testWeightAndColdSurviveDiskReopenAndDuplication() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("TallyServing-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let configuration = ModelConfiguration(url: folder.appendingPathComponent("Library.store"), cloudKitDatabase: .none)
        do {
            let writer = try LibraryStore.container(configuration: configuration)
            var draft = DrinkDraft(); draft.name = "Chocolate"; draft.amount = "45.5"; draft.amountUnit = .grams
            draft.category = .snack; draft.servingStyle = .cold
            try DrinkLibrary.save(draft, in: writer.mainContext)
        }
        let reader = try LibraryStore.container(configuration: configuration)
        let stored = try XCTUnwrap(reader.mainContext.fetch(FetchDescriptor<SavedDrink>()).first)
        XCTAssertEqual(stored.weightG, 45.5)
        XCTAssertNil(stored.volumeMl)
        XCTAssertEqual(stored.servingStyle, .cold)
        let copy = try DrinkLibrary.duplicate(stored, in: reader.mainContext)
        XCTAssertNotEqual(copy.id, stored.id)
        XCTAssertEqual(copy.weightG, 45.5)
        XCTAssertNil(copy.volumeMl)
        XCTAssertEqual(copy.servingStyle, .cold)
        XCTAssertNotNil(UIImage(named: "Snack"))
    }

    func testPreWeightDiskStoreMigratesWithoutChangingLegacyAmount() throws {
        // Freeze the actual prior model so this tests an added column, not a store created with today's schema.
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("TallyAmountMigration-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let configuration = ModelConfiguration(url: folder.appendingPathComponent("Library.store"), cloudKitDatabase: .none)
        let id = UUID()
        do {
            let legacy = try ModelContainer(for: PreWeightSchema.SavedDrink.self, configurations: configuration)
            legacy.mainContext.insert(PreWeightSchema.SavedDrink(id: id, name: "Coffee", volumeMl: 330,
                category: .coffee, servingStyle: .iced, nutrition: .init(caffeine: 100), timesLogged: 7))
            try legacy.mainContext.save()
        }
        let upgraded = try LibraryStore.container(configuration: configuration)
        let stored = try XCTUnwrap(upgraded.mainContext.fetch(FetchDescriptor<SavedDrink>()).first)
        XCTAssertEqual(stored.id, id)
        XCTAssertEqual(stored.volumeMl, 330)
        XCTAssertNil(stored.weightG)
        // The same legacy store also upgrades through the optional sodium column.
        XCTAssertNil(stored.sodiumMg)
        XCTAssertEqual(stored.servingStyle, .iced)
        XCTAssertEqual(stored.caffeineMg, 100)
        XCTAssertEqual(stored.timesLogged, 7)
        XCTAssertEqual(DrinkDraft(drink: stored).amountUnit, .millilitres)
    }
}

/// Frozen pre-weight model: changing this would invalidate the additive migration regression test.
private enum PreWeightSchema {
    @Model
    final class SavedDrink {
        @Attribute(.unique) var id: UUID
        var name: String
        var brandOrLocation: String?
        var size: String?
        var volumeMl: Double?
        var categoryRaw: String
        var servingStyleRaw: String
        var caffeineMg: Double?
        var caloriesKcal: Double?
        var sugarG: Double?
        var carbohydratesG: Double?
        var proteinG: Double?
        var totalFatG: Double?
        var saturatedFatG: Double?
        var fibreG: Double?
        var estimatedNutrients: [String]
        var notes: String?
        var isFavourite: Bool
        var createdAt: Date
        var updatedAt: Date
        var lastLoggedAt: Date?
        var timesLogged: Int

        init(id: UUID = UUID(), name: String, brandOrLocation: String? = nil, size: String? = nil,
             volumeMl: Double? = nil, category: DrinkCategory = .other, servingStyle: ServingStyle = .other,
             nutrition: NutritionValues = .init(), notes: String? = nil, isFavourite: Bool = false,
             createdAt: Date = .now, updatedAt: Date = .now, lastLoggedAt: Date? = nil, timesLogged: Int = 0) {
            self.id = id
            self.name = name
            self.brandOrLocation = brandOrLocation
            self.size = size
            self.volumeMl = volumeMl
            self.categoryRaw = category.rawValue
            self.servingStyleRaw = servingStyle.rawValue
            caffeineMg = nutrition.caffeine
            caloriesKcal = nutrition.calories
            sugarG = nutrition.sugar
            carbohydratesG = nutrition.carbohydrates
            proteinG = nutrition.protein
            totalFatG = nutrition.totalFat
            saturatedFatG = nutrition.saturatedFat
            fibreG = nutrition.fibre
            estimatedNutrients = nutrition.estimated.map(\.rawValue).sorted()
            self.notes = notes
            self.isFavourite = isFavourite
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.lastLoggedAt = lastLoggedAt
            self.timesLogged = timesLogged
        }

        var category: DrinkCategory { DrinkCategory(rawValue: categoryRaw) ?? .other }
        var servingStyle: ServingStyle { ServingStyle(rawValue: servingStyleRaw) ?? .other }
        var nutrition: NutritionValues {
            get { .init(caffeine: caffeineMg, calories: caloriesKcal, sugar: sugarG, carbohydrates: carbohydratesG,
                        protein: proteinG, totalFat: totalFatG, saturatedFat: saturatedFatG, fibre: fibreG,
                        estimated: Set(estimatedNutrients.compactMap(Nutrient.init(rawValue:)))) }
            set {
                caffeineMg = newValue.caffeine; caloriesKcal = newValue.calories; sugarG = newValue.sugar
                carbohydratesG = newValue.carbohydrates; proteinG = newValue.protein; totalFatG = newValue.totalFat
                saturatedFatG = newValue.saturatedFat; fibreG = newValue.fibre
                estimatedNutrients = newValue.estimated.map(\.rawValue).sorted()
            }
        }
    }
}
