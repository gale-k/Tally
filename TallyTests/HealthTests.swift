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
    func testExplicitZeroCreatesSampleButUnknownDoesNot() throws {
        XCTAssertEqual(try HealthKitStore.makeSamples(for: .init(name: "Chai", nutrition: .init(caffeine: 0))).count, 1)
        XCTAssertThrowsError(try HealthKitStore.makeSamples(for: .init(name: "Unknown", nutrition: .init())))
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
    func requestAccess() async throws {}
    func writeStatus(for nutrient: Nutrient) -> NutritionWriteStatus { .allowed }
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
