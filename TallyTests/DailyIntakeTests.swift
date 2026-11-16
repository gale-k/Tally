import XCTest
import SwiftUI
@testable import Tally

/// Comparison tests deliberately include absent data, real zeroes, custom goals, and over-100% totals.
final class DailyIntakeTests: XCTestCase {
    func testAdultPresetAndMeanings() throws {
        XCTAssertEqual(DailyIntakeReference.all.count, 9)
        let expected: [Nutrient: Double] = [.calories: 2_000, .protein: 50, .sugar: 90, .caffeine: 400,
                                           .carbohydrates: 260, .totalFat: 70, .saturatedFat: 20, .fibre: 30, .sodium: 2_400]
        for reference in DailyIntakeReference.all {
            XCTAssertEqual(reference.defaultValue, expected[reference.nutrient])
            XCTAssertTrue(reference.isValid(reference.defaultValue))
            XCTAssertEqual(reference.label(for: reference.defaultValue), reference.isMaximum ? "Daily maximum" : "Daily target")
            XCTAssertEqual(reference.label(for: reference.defaultValue / 2), reference.isMaximum ? "Daily maximum" : "Daily target")
        }
        XCTAssertEqual(try reference(.sugar).title, "Total Sugars")
        XCTAssertEqual(try reference(.protein).label(for: 50), "Daily target")
        XCTAssertEqual(try reference(.fibre).label(for: 30), "Daily target")
        XCTAssertEqual(try reference(.caffeine).valueKey, "dailyCaffeineTarget")
    }

    func testBelowAtAboveAndZero() throws {
        let reference = try reference(.calories)
        let below = try XCTUnwrap(DailyIntakeProgress(consumed: 500, target: 2_000))
        XCTAssertEqual(below.percentage, 25)
        XCTAssertEqual(below.difference, 1_500)
        XCTAssertTrue(below.status(for: reference).contains("to target"))
        let equal = try XCTUnwrap(DailyIntakeProgress(consumed: 2_000, target: 2_000))
        XCTAssertEqual(equal.status(for: reference), "Target met")
        let above = try XCTUnwrap(DailyIntakeProgress(consumed: 3_000, target: 2_000))
        XCTAssertEqual(above.percentage, 150)
        XCTAssertEqual(above.fraction, 1)
        XCTAssertEqual(above.difference, 1_000)
        XCTAssertTrue(above.status(for: reference).contains("above target"))
        XCTAssertEqual(DailyIntakeProgress(consumed: 0, target: 2_000)?.percentage, 0)
        XCTAssertNil(DailyIntakeProgress(consumed: nil, target: 2_000))
    }

    func testProteinAndFibreNeverBecomeSafetyCeilings() throws {
        for nutrient in [Nutrient.protein, .fibre] {
            let reference = try reference(nutrient)
            for target in [reference.defaultValue, reference.defaultValue / 2] {
                let progress = try XCTUnwrap(DailyIntakeProgress(consumed: target * 2, target: target))
                let status = progress.status(for: reference)
                XCTAssertFalse(status.contains("over"))
                XCTAssertTrue(status.contains("reached") || status.contains("met"))
                XCTAssertEqual(progress.percentage, 200)
            }
        }
        let caffeine = try reference(.caffeine)
        XCTAssertEqual(DailyIntakeProgress(consumed: 200, target: 400)?.status(for: caffeine), "200 mg to daily maximum")
        XCTAssertEqual(DailyIntakeProgress(consumed: 400, target: 400)?.status(for: caffeine), "At daily maximum")
        XCTAssertTrue(try XCTUnwrap(DailyIntakeProgress(consumed: 500, target: 400)).status(for: caffeine).contains("over daily maximum"))
    }

    // Salt and sodium share a single persisted comparison and the same finite validation.
    func testSodiumMaximumAndSaltConversion() throws {
        let sodium = try reference(.sodium)
        XCTAssertEqual(sodium.defaultValue, 2_400)
        XCTAssertEqual(sodium.saltEquivalent(2_400), "6 g salt")
        XCTAssertEqual(try sodium.parse("6", locale: Locale(identifier: "en_GB"), sodiumUnit: .salt), 2_400)
        XCTAssertEqual(try sodium.parse("1,5", locale: Locale(identifier: "fr_FR"), sodiumUnit: .salt), 600)
        XCTAssertThrowsError(try sodium.parse("0", sodiumUnit: .salt))
        XCTAssertThrowsError(try sodium.parse("26", sodiumUnit: .salt))
        XCTAssertEqual(DailyIntakeProgress(consumed: 3_000, target: 2_400)?.status(for: sodium), "600 mg over daily maximum")
        for nutrient in [Nutrient.sugar, .totalFat, .saturatedFat, .caffeine, .sodium] {
            XCTAssertTrue(try reference(nutrient).label(for: reference(nutrient).defaultValue).lowercased().contains("maximum"))
        }
    }

    func testMalformedTargetsAndLocale() throws {
        let reference = try reference(.protein)
        for text in ["", " ", "0", "-1", "NaN", "inf", "1e300", "10g", "1.2.3", "10001"] {
            XCTAssertThrowsError(try reference.parse(text, locale: Locale(identifier: "en_GB")), text)
        }
        XCTAssertEqual(try reference.parse("12,5", locale: Locale(identifier: "fr_FR")), 12.5)
        XCTAssertEqual(try reference.parse(" .25 ", locale: Locale(identifier: "en_GB")), 0.25)
        for value in [0.0, -1, .infinity, .nan, 10_001] { XCTAssertFalse(reference.isValid(value)) }
        for target in [0.0, -1, .infinity, .nan] { XCTAssertNil(DailyIntakeProgress(consumed: 1, target: target)) }
        for total in [-1.0, .infinity, .nan] { XCTAssertNil(DailyIntakeProgress(consumed: total, target: 50)) }
        XCTAssertNil(DailyIntakeProgress(consumed: .greatestFiniteMagnitude, target: 0.01))
    }

    @MainActor
    func testAppStorageUsesLegacyCaffeineAndRetainsIndependentLocalChoices() throws {
        let suite = "Tally.DailyIntakeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(275.0, forKey: "dailyCaffeineTarget")
        defaults.set(false, forKey: "showSugar")
        for reference in DailyIntakeReference.all {
            let value = AppStorage(wrappedValue: reference.defaultValue, reference.valueKey, store: defaults)
            let enabled = AppStorage(wrappedValue: true, reference.enabledKey, store: defaults)
            XCTAssertEqual(value.wrappedValue, reference.nutrient == .caffeine ? 275 : reference.defaultValue)
            XCTAssertTrue(enabled.wrappedValue)
            value.wrappedValue = reference.defaultValue / 2
            enabled.wrappedValue = false
        }
        let reopened = try XCTUnwrap(UserDefaults(suiteName: suite))
        for reference in DailyIntakeReference.all {
            XCTAssertEqual(AppStorage(wrappedValue: reference.defaultValue, reference.valueKey, store: reopened).wrappedValue, reference.defaultValue / 2)
            XCTAssertFalse(AppStorage(wrappedValue: true, reference.enabledKey, store: reopened).wrappedValue)
        }
        XCTAssertFalse(reopened.bool(forKey: "showSugar"))
        XCTAssertNil(reopened.object(forKey: "healthPermissionsRequested"))
    }

    @MainActor
    func testMidnightDropsYesterdayOnFailureAndRefreshRecovers() async throws {
        let store = FakeNutritionStore()
        let date = Calendar.current.startOfDay(for: .now).addingTimeInterval(60)
        store.saved = [.init(name: "Protein", nutrition: .init(protein: 25, estimated: [.protein]), date: date)]
        let manager = HealthKitManager(client: store, defaults: nil)
        try await manager.requestAccess()
        await manager.refresh(now: date.addingTimeInterval(60))
        XCTAssertEqual(manager.today.protein, 25)
        XCTAssertTrue(manager.today.estimated.contains(.protein))
        store.queryError = HealthAccessError.unavailable
        await manager.refresh(now: date.addingTimeInterval(120))
        XCTAssertEqual(manager.today.protein, 25)
        XCTAssertNotNil(manager.queryError)
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: date)!
        await manager.refresh(now: tomorrow)
        XCTAssertNil(manager.today.protein)
        XCTAssertNotNil(manager.queryError)
        store.queryError = nil
        store.saved.append(.init(name: "Zero", nutrition: .init(protein: 0), date: tomorrow))
        await manager.refresh(now: tomorrow.addingTimeInterval(60))
        XCTAssertEqual(manager.today.protein, 0)
        XCTAssertNil(manager.queryError)
    }

    func testAutumnDaylightSavingAndAllSourceEstimatedTotals() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-25T12:00:00Z"))
        let day = DateWindows.day(containing: date, calendar: calendar)
        XCTAssertEqual(day.duration, 25 * 3_600)
        let records = [("own", day.start, 10.0), ("other", day.end.addingTimeInterval(-1), 15.0), ("other", day.end, 90.0)].map {
            HealthSample(id: UUID(), nutrient: .protein, value: $0.2, date: $0.1, sourceName: $0.0,
                         sourceBundle: $0.0, isEstimated: $0.0 == "other")
        }
        let nutrition = try HealthAggregation.totals(records.filter { DateWindows.contains($0.date, in: day) })
        XCTAssertEqual(nutrition.protein, 25)
        XCTAssertTrue(nutrition.estimated.contains(.protein))
        XCTAssertEqual(DailyIntakeProgress(consumed: nutrition.protein, target: 50)?.percentage, 50)
    }

    private func reference(_ nutrient: Nutrient) throws -> DailyIntakeReference {
        try XCTUnwrap(DailyIntakeReference.all.first { $0.nutrient == nutrient })
    }
}
