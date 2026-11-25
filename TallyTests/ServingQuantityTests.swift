import XCTest
@testable import Tally

final class ServingQuantityTests: XCTestCase {
    func testLocalizedFractionsAndInvalidQuantities() {
        let english = Locale(identifier: "en_GB")
        XCTAssertEqual(ServingQuantity.parse(".5", locale: english), 0.5)
        XCTAssertEqual(ServingQuantity.parse(" 2.5 ", locale: english), 2.5)
        XCTAssertEqual(ServingQuantity.parse("1,5", locale: Locale(identifier: "fr_FR")), 1.5)
        let arabic = Locale(identifier: "ar_SA")
        XCTAssertEqual(ServingQuantity.parse("١\(arabic.decimalSeparator ?? ".")٥", locale: arabic), 1.5)
        for invalid in ["", "0", "-1", "nan", "inf", "1.2.3", "1,000", "1e2", "1/2"] {
            XCTAssertNil(ServingQuantity.parse(invalid, locale: english), "Expected to reject \(invalid)")
        }
    }

    func testLoggingScalesEveryNutrientAndKeepsMissingZeroAndEstimatedValues() throws {
        let original = NutritionValues(caffeine: 40, calories: 125, sugar: 0, carbohydrates: 12, protein: 4,
                                       totalFat: 5, saturatedFat: 2, fibre: 3, sodium: 160, estimated: [.caffeine, .protein])
        let event = ConsumptionDraft(name: "Snack", nutrition: original, quantity: 2.5)
        try event.validate()
        for nutrient in Nutrient.allCases {
            XCTAssertEqual(event.nutrition[nutrient], original[nutrient].map { $0 * 2.5 }, nutrient.rawValue)
        }
        XCTAssertEqual(event.perServingNutrition, original)
        XCTAssertEqual(event.nutrition.estimated, original.estimated)
        XCTAssertNil(NutritionValues(calories: 125).scaled(by: 0.5).caffeine)
    }

    func testQuantityValidationAppliesLabelInputLimitsBeforeScaling() throws {
        let original = NutritionValues(caffeine: 6_000)
        let event = ConsumptionDraft(name: "Example", nutrition: original, quantity: 2)
        XCTAssertEqual(event.nutrition.caffeine, 12_000)
        try event.validate()
        for invalid in [0, -1, Double.nan, Double.infinity, Double.greatestFiniteMagnitude] {
            XCTAssertThrowsError(try ConsumptionDraft(name: "Example", nutrition: original, quantity: invalid).validate())
        }
        // A quantity that underflows a positive amount would silently remove that nutrient from Health.
        let tiny = ConsumptionDraft(name: "Example", nutrition: .init(calories: 1, protein: 0.1),
                                    quantity: Double.leastNonzeroMagnitude)
        XCTAssertThrowsError(try tiny.validate())
    }

    @MainActor
    func testStructuredAmountAndLegacyLabelCanDisplayOriginalAndTotal() {
        let locale = Locale(identifier: "en_GB")
        let biscuits = SavedDrink(name: "Chocolate Biscuits", size: "One biscuit", weightG: 25)
        XCTAssertEqual(biscuits.servingAmount?.formatted(locale: locale), "25 g")
        XCTAssertEqual(biscuits.servingAmount?.formatted(quantity: 3, locale: locale), "75 g")
        let oldTemplate = SavedDrink(name: "Latte", size: "330 ml")
        XCTAssertEqual(oldTemplate.servingAmount?.formatted(quantity: 0.5, locale: locale), "165 ml")
        XCTAssertNil(ServingAmount(size: "Medium"))
    }

    func testHistoryUsesOriginalSnapshotAndRecomputesTotalsWithoutRoundingDrift() throws {
        let now = Date.now
        let date = now.addingTimeInterval(-60)
        let eventID = UUID()
        let sample = HealthSample(id: UUID(), nutrient: .sodium, value: 12.5, date: date,
                                  sourceName: "Tally", sourceBundle: "test.tally", eventID: eventID.uuidString,
                                  drinkName: "Soup", isEstimated: true, servingQuantity: 2.5,
                                  servingAmount: .init(value: 25, unit: .grams), perServingValue: 5,
                                  expectedNutrients: [.sodium])
        let history = try NutritionHistorySnapshot(samples: [sample], ownBundle: "test.tally", limitedDates: [:],
                                                   now: now, calendar: .current)
        let day = try XCTUnwrap(history.days.first { !$0.events.isEmpty })
        let entry = try XCTUnwrap(day.events.first)
        XCTAssertEqual(day.totals.sodium, 12.5)
        XCTAssertEqual(entry.nutrition.sodium, 12.5)
        XCTAssertEqual(entry.quantity, 2.5)
        XCTAssertTrue(entry.canModify)
        let resized = try entry.withQuantity(1.5)
        XCTAssertEqual(resized.id, eventID)
        XCTAssertEqual(resized.date, date)
        XCTAssertEqual(resized.nutrition.sodium, 7.5)
        XCTAssertEqual(resized.nutrition.estimated, [.sodium])
        let repeated = try entry.relogged(at: now)
        XCTAssertNotEqual(repeated.id, eventID)
        XCTAssertEqual(repeated.date, now)
        XCTAssertEqual(repeated.quantity, 2.5)
        XCTAssertEqual(repeated.nutrition, entry.nutrition)

        // If an expected sample disappears in Health, keep visible totals but avoid editing a partial event.
        var partial = sample
        partial.expectedNutrients = [.sodium, .calories]
        let partialEntry = try XCTUnwrap(HealthAggregation.events([partial], ownBundle: "test.tally").first)
        XCTAssertEqual(partialEntry.nutrition.sodium, 12.5)
        XCTAssertFalse(partialEntry.canModify)
        XCTAssertFalse(partialEntry.canLogAgain)
    }

    func testExistingHistoryDefaultsToOneServingAndIgnoresCopiedMetadataFromOtherApps() throws {
        let old = HealthSample(id: UUID(), nutrient: .calories, value: 120, date: .now,
                               sourceName: "Tally", sourceBundle: "test.tally", drinkName: "Biscuits", size: "25 g",
                               isEstimated: false)
        var other = old
        other.id = UUID()
        other.sourceBundle = "test.other"
        other.servingQuantity = 3
        let events = try HealthAggregation.events([old, other], ownBundle: "test.tally")
        let entry = try XCTUnwrap(events.first(where: \.isFromTally))
        XCTAssertEqual(entry.quantity, 1)
        XCTAssertEqual(try entry.withQuantity(0.5).nutrition.calories, 60)
        XCTAssertEqual(entry.servingAmount?.value, 25)
        let external = try XCTUnwrap(events.first { !$0.isFromTally })
        XCTAssertEqual(external.quantity, 1)
        XCTAssertFalse(external.canModify)
        XCTAssertFalse(external.canLogAgain)
    }
}
