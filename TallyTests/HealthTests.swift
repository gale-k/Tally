import XCTest
import HealthKit
@testable import Tally

final class HealthTests: XCTestCase {
    func testGroupingUsesOnlyOwnEventIdentifiers() throws {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let records = [record(.caffeine, 100, date, "own", "same"), record(.calories, 220, date, "own", "same"),
                       record(.sugar, 24, date, "other", "same"), record(.protein, 6, date, "other", "same")]
        let grouped = try HealthAggregation.events(records, ownBundle: "own")
        XCTAssertEqual(grouped.count, 3)
        let own = try XCTUnwrap(grouped.first(where: \.isFromTally))
        XCTAssertEqual(own.nutrition.caffeine, 100)
        XCTAssertEqual(own.nutrition.calories, 220)
        XCTAssertNil(own.nutrition.sugar)
    }
    func testDistinctOwnEventsAtSameTimeRemainSeparate() throws {
        let now = Date.now
        let events = try HealthAggregation.events([record(.caffeine, 100, now, "own", "one"),
                                                  record(.caffeine, 110, now, "own", "two")], ownBundle: "own")
        XCTAssertEqual(events.count, 2)
    }
    func testHalfOpenDayAndDaylightSaving() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        let date = ISO8601DateFormatter().date(from: "2026-03-29T12:00:00Z")!
        let day = DateWindows.day(containing: date, calendar: calendar)
        XCTAssertEqual(day.duration, 23 * 60 * 60)
        XCTAssertTrue(DateWindows.contains(day.start, in: day))
        XCTAssertFalse(DateWindows.contains(day.end, in: day))
    }
    func testUnknownTotalsRemainUnknown() throws {
        let empty = try HealthAggregation.totals([])
        XCTAssertNil(empty.caffeine)
        let result = try HealthAggregation.totals([record(.caffeine, 0, .now)])
        XCTAssertEqual(result.caffeine, 0)
        XCTAssertNil(result.calories)
    }
    func testRejectsInvalidOrOverflowingExternalData() {
        XCTAssertThrowsError(try HealthAggregation.totals([record(.caffeine, .infinity, .now)]))
        XCTAssertThrowsError(try HealthAggregation.totals([record(.caffeine, .greatestFiniteMagnitude, .now), record(.caffeine, .greatestFiniteMagnitude, .now)]))
    }
    @MainActor
    func testSampleConversionUsesKnownFieldsAndSharedTimestamp() throws {
        let date = Date.now.addingTimeInterval(-60)
        let draft = ConsumptionDraft(name: "Mocha", brand: "Fuel", nutrition: .init(caffeine: 100, calories: 220, sugar: 24, protein: 6, estimated: [.caffeine]), date: date)
        let samples = try HealthKitStore.makeSamples(for: draft)
        XCTAssertEqual(samples.count, 4)
        XCTAssertTrue(samples.allSatisfy { $0.startDate == date && $0.endDate == date })
        let caffeine = try XCTUnwrap(samples.first { $0.quantityType == Nutrient.caffeine.healthType })
        XCTAssertEqual(caffeine.quantity.doubleValue(for: .gramUnit(with: .milli)), 100)
        XCTAssertEqual(caffeine.quantity.doubleValue(for: .gram()), 0.1, accuracy: 0.00001)
        XCTAssertEqual(caffeine.metadata?[HKMetadataKeyFoodType] as? String, "Mocha")
        XCTAssertEqual(caffeine.metadata?[HealthKitStore.eventKey] as? String, draft.id.uuidString)
        XCTAssertEqual(caffeine.metadata?[HealthKitStore.estimatedKey] as? Bool, true)
    }
    @MainActor
    func testWritesRequireAtLeastOnePositiveAmount() {
        // A zero-only or empty entry must fail instead of reporting a successful empty Health write.
        for nutrition in [NutritionValues(caffeine: 0, sugar: 0), NutritionValues()] {
            XCTAssertThrowsError(try HealthKitStore.makeSamples(for: .init(name: "Chai", nutrition: nutrition))) { error in
                guard case DrinkValidationError.noNutrition = error else { return XCTFail("Unexpected error: \(error)") }
            }
        }
    }
    @MainActor
    func testCoordinatorRequestsThenSavesAndRefreshes() async throws {
        let store = FakeNutritionStore()
        let manager = HealthKitManager(client: store, defaults: nil)
        try await manager.log(.init(name: "Coffee", nutrition: .init(caffeine: 100)))
        XCTAssertTrue(manager.permissionsRequested)
        XCTAssertEqual(store.saved.count, 1)
        XCTAssertEqual(manager.today.caffeine, 100)
        XCTAssertEqual(manager.events.count, 1)
    }
    @MainActor
    func testZeroAmountDoesNotReopenHealthPermissions() async throws {
        let store = FakeNutritionStore()
        let manager = HealthKitManager(client: store, defaults: nil)
        try await manager.requestAccess()
        // Simulate a type added after this user last reviewed their Health permissions.
        store.writeStatuses[.sodium] = .notRequested
        try await manager.log(.init(name: "Lunch Bowl", nutrition: .init(calories: 380, sodium: 0)))
        XCTAssertEqual(store.accessRequests, 1)
        XCTAssertEqual(store.writeStatus(for: .sodium), .notRequested)
        XCTAssertEqual(manager.today.calories, 380)
    }
    @MainActor
    func testFailedSaveDoesNotCreateHistory() async {
        let store = FakeNutritionStore()
        store.saveError = HealthAccessError.writeDenied(["Caffeine"])
        let manager = HealthKitManager(client: store, defaults: nil)
        do { try await manager.log(.init(name: "Coffee", nutrition: .init(caffeine: 100))); XCTFail("Expected failure") } catch {}
        XCTAssertTrue(store.saved.isEmpty)
        XCTAssertTrue(manager.events.isEmpty)
        XCTAssertFalse(manager.isSaving)
    }
    @MainActor
    func testQueryFailureHasVisibleError() async throws {
        let store = FakeNutritionStore()
        store.queryError = HealthAccessError.unavailable
        let manager = HealthKitManager(client: store, defaults: nil)
        try await manager.requestAccess()
        XCTAssertNotNil(manager.queryError)
        XCTAssertNil(manager.today.caffeine)
    }
    func testTrendRetainsEstimatesAndDoesNotInventUnknownDays() throws {
        let now = Date.now
        var sample = record(.caffeine, 100, now.addingTimeInterval(-1))
        sample.isEstimated = true
        let days = try HealthAggregation.caffeineDays([sample], count: 2, now: now)
        XCTAssertNil(days[0].total)
        XCTAssertEqual(days[1].total, 100)
        XCTAssertTrue(days[1].isEstimated)
    }
    func testFutureAndEmptyConsumptionAreRejected() {
        XCTAssertThrowsError(try ConsumptionDraft(name: "Coffee", nutrition: .init(caffeine: 100), date: Date.now.addingTimeInterval(3_600)).validate())
        XCTAssertThrowsError(try ConsumptionDraft(name: "Unknown", nutrition: .init()).validate())
    }
    @MainActor
    func testFoodWritesOnlyPositiveNutrientsAndKeepsItsName() throws {
        // A known zero, even when marked estimated, is skipped alongside blank fields.
        let food = ConsumptionDraft(name: "Lunch Bowl", nutrition: .init(calories: 380, sugar: 0, protein: 24, estimated: [.sugar, .protein]))
        let samples = try HealthKitStore.makeSamples(for: food)
        XCTAssertEqual(samples.map(\.quantityType), [Nutrient.calories.healthType, Nutrient.protein.healthType])
        let protein = try XCTUnwrap(samples.first { $0.quantityType == Nutrient.protein.healthType })
        XCTAssertEqual(protein.quantity.doubleValue(for: .gram()), 24)
        XCTAssertEqual(protein.metadata?[HKMetadataKeyFoodType] as? String, "Lunch Bowl")
        XCTAssertEqual(protein.metadata?[HealthKitStore.estimatedKey] as? Bool, true)
        XCTAssertTrue(samples.allSatisfy { $0.startDate == food.date })
    }
    func testHistoricalNameAndLegacyGroupingRemainIntact() throws {
        let date = Date.now
        let samples = [record(.caffeine, 100, date), record(.calories, 220, date)]
        let event = try XCTUnwrap(HealthAggregation.events(samples, ownBundle: "own").first)
        XCTAssertEqual(event.name, "Coffee")
        XCTAssertEqual(event.nutrition.calories, 220)
        XCTAssertEqual(event.nutrition.caffeine, 100)
    }
    // A nutrient drill-down must reconcile with the same day's samples without merging other apps.
    func testDailyContributionGroupingAndEstimates() throws {
        let now = Date.now
        var estimated = record(.sugar, 3, now, "own", "food")
        estimated.isEstimated = true
        var unnamed = record(.sugar, 4, now, "other", "food")
        unnamed.drinkName = nil
        let named = record(.sugar, 5, now, "other", "food")
        let records = [estimated, record(.calories, 100, now, "own", "food"), unnamed, named,
                       record(.sugar, 0, now, "own", "zero")]
        let events = try HealthAggregation.events(records, ownBundle: "own", unnamedExternal: "Unnamed nutrition entry")
        let positive = events.filter { ($0.nutrition.sugar ?? 0) > 0 }
        XCTAssertEqual(positive.count, 3)
        XCTAssertEqual(positive.compactMap { $0.nutrition.sugar }.reduce(0, +), try HealthAggregation.totals(records).sugar)
        XCTAssertTrue(try XCTUnwrap(positive.first(where: \.isFromTally)).nutrition.estimated.contains(.sugar))
        XCTAssertEqual(positive.filter { $0.name == "Unnamed nutrition entry" }.count, 1)
        XCTAssertEqual(positive.filter { $0.name == "Coffee" && !$0.isFromTally }.count, 1)
    }
    private func record(_ nutrient: Nutrient, _ value: Double, _ date: Date, _ bundle: String = "own", _ event: String? = nil) -> HealthSample {
        .init(id: UUID(), nutrient: nutrient, value: value, date: date, sourceName: bundle, sourceBundle: bundle,
              eventID: event, drinkName: "Coffee", isEstimated: false)
    }
}

@MainActor
final class FakeNutritionStore: NutritionStore {
    var isAvailable = true
    var ownBundleIdentifier = "own"
    var saved: [ConsumptionDraft] = []
    var saveError: Error?
    var queryError: Error?
    // Tests can model an undecided newly supported type separately from an explicit denial.
    var accessRequests = 0
    var writeStatuses: [Nutrient: NutritionWriteStatus] = [:]
    func requestAccess() async throws {
        accessRequests += 1
        for nutrient in Nutrient.allCases where writeStatuses[nutrient] == .notRequested { writeStatuses[nutrient] = .allowed }
    }
    func writeStatus(for nutrient: Nutrient) -> NutritionWriteStatus { writeStatuses[nutrient] ?? .allowed }
    func save(_ event: ConsumptionDraft) async throws {
        if let saveError { throw saveError }
        saved.append(event)
    }
    func samples(in range: DateInterval) async throws -> [HealthSample] {
        if let queryError { throw queryError }
        return saved.flatMap { event in
            event.nutrition.knownNutrients.map { nutrient in
                HealthSample(id: UUID(), nutrient: nutrient, value: event.nutrition[nutrient]!, date: event.date,
                             sourceName: "Tally", sourceBundle: "own", eventID: event.id.uuidString, drinkName: event.name,
                             isEstimated: event.nutrition.estimated.contains(nutrient))
            }
        }
    }
    func limitedReadDates() async throws -> [Nutrient: Date] { [:] }
}
