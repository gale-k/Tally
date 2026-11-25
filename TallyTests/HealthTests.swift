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
    func testServingSamplesCarryTotalsAndStableSyncMetadata() throws {
        let date = Date.now.addingTimeInterval(-60)
        let base = NutritionValues(calories: 100, protein: 8, sodium: 0, estimated: [.protein])
        let original = ConsumptionDraft(name: "Biscuits", nutrition: base, date: date, quantity: 1.5,
                                        servingAmount: .init(value: 25, unit: .grams))
        let modified = ConsumptionDraft(id: original.id, name: original.name, nutrition: base, date: date, quantity: 2.5,
                                        servingAmount: original.servingAmount)
        let initialSamples = try HealthKitStore.makeSamples(for: original)
        let replacement = try HealthKitStore.makeSamples(for: modified, syncVersion: 2)
        XCTAssertEqual(replacement.count, 2)
        for (previous, current) in zip(initialSamples, replacement) {
            // Versioning is per nutrient. Different quantities replace the same sample IDs in Health.
            XCTAssertEqual(previous.metadata?[HKMetadataKeySyncIdentifier] as? String, current.metadata?[HKMetadataKeySyncIdentifier] as? String)
            XCTAssertEqual((current.metadata?[HKMetadataKeySyncVersion] as? NSNumber)?.int64Value, 2)
            XCTAssertEqual(current.metadata?[HealthKitStore.quantityKey] as? Double, 2.5)
            XCTAssertEqual(current.metadata?[HealthKitStore.servingValueKey] as? Double, 25)
            XCTAssertEqual(current.metadata?[HealthKitStore.servingUnitKey] as? String, "g")
            let expected = try XCTUnwrap(current.metadata?[HealthKitStore.nutrientsKey] as? String)
            XCTAssertEqual(Set(expected.split(separator: ",")), ["calories", "protein"])
        }
        let protein = try XCTUnwrap(replacement.first { $0.quantityType == Nutrient.protein.healthType })
        XCTAssertEqual(protein.metadata?[HealthKitStore.perServingKey] as? Double, 8)
        XCTAssertEqual(protein.quantity.doubleValue(for: .gram()), 20)
        XCTAssertNotEqual(replacement[0].metadata?[HKMetadataKeySyncIdentifier] as? String, replacement[1].metadata?[HKMetadataKeySyncIdentifier] as? String)
    }

    @MainActor
    func testFailedLegacySampleDeletionRollsBackStagedSamples() async throws {
        let old = try HealthKitStore.makeSamples(for: .init(name: "Coffee", nutrition: .init(caffeine: 100)))
        let staged = try HealthKitStore.makeSamples(for: .init(name: "Coffee", nutrition: .init(caffeine: 100), quantity: 1.5))
        var persisted = Set(old.map(\.uuid))
        do {
            try await HealthKitStore.replaceLegacySamples(old, with: staged, save: { samples in
                persisted.formUnion(samples.map(\.uuid))
            }, delete: { samples in
                if samples.map(\.uuid) == old.map(\.uuid) { throw HealthAccessError.unavailable }
                persisted.subtract(samples.map(\.uuid))
            })
            XCTFail("Expected deletion to fail")
        } catch HealthAccessError.unavailable {}
        // Only the originals survive, so a retry cannot create duplicate Health records.
        XCTAssertEqual(persisted, Set(old.map(\.uuid)))
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
    func testCoordinatorEditsRepeatsAndDeletesServingSnapshots() async throws {
        let store = FakeNutritionStore()
        let manager = HealthKitManager(client: store, defaults: nil)
        let draft = ConsumptionDraft(name: "Coffee", nutrition: .init(caffeine: 100, calories: 20),
                                     date: .now.addingTimeInterval(-60), quantity: 1.5)
        try await manager.log(draft)
        let original = try XCTUnwrap(manager.events.first)
        XCTAssertEqual(original.quantity, 1.5)
        XCTAssertEqual(original.nutrition.caffeine, 150)

        try await manager.updateQuantity(original, quantity: 2.5)
        let updated = try XCTUnwrap(manager.events.first)
        XCTAssertEqual(manager.events.count, 1)
        XCTAssertEqual(updated.id, original.id)
        XCTAssertEqual(updated.date, original.date)
        XCTAssertEqual(updated.nutrition.caffeine, 250)
        XCTAssertEqual(store.saved.count, 1)
        XCTAssertEqual(store.saved[0].nutrition.calories, 50)
        XCTAssertEqual(store.saved[0].perServingNutrition.calories, 20)

        try await manager.logAgain(updated)
        XCTAssertEqual(manager.events.count, 2)
        let repeated = try XCTUnwrap(manager.events.first)
        XCTAssertNotEqual(repeated.id, updated.id)
        XCTAssertGreaterThan(repeated.date, updated.date)
        XCTAssertEqual(repeated.quantity, 2.5)
        XCTAssertEqual(repeated.nutrition, updated.nutrition)

        try await manager.delete(repeated)
        XCTAssertEqual(manager.events.map(\.id), [updated.id])
        XCTAssertEqual(store.saved.map(\.id), [draft.id])
        do {
            try await manager.updateQuantity(original, quantity: 5)
            XCTFail("Expected the original samples to be stale")
        } catch HealthAccessError.entryChanged {}
        XCTAssertEqual(manager.events.first?.quantity, 2.5)
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
        let events = try HealthAggregation.events(records, ownBundle: "own")
        let positive = events.filter { ($0.nutrition.sugar ?? 0) > 0 }
        XCTAssertEqual(positive.count, 3)
        XCTAssertEqual(positive.compactMap { $0.nutrition.sugar }.reduce(0, +), try HealthAggregation.totals(records).sugar)
        XCTAssertTrue(try XCTUnwrap(positive.first(where: \.isFromTally)).nutrition.estimated.contains(.sugar))
        XCTAssertEqual(positive.filter { $0.contributionName == "Unnamed nutrition entry" }.count, 1)
        XCTAssertEqual(positive.filter { $0.contributionName == "Coffee" && !$0.isFromTally }.count, 1)
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
    var fixtureSamples: [HealthSample] = []
    var readLimits: [Nutrient: Date] = [:]
    // Keep sample UUIDs stable until a Health operation replaces or deletes the samples.
    private var savedSamples: [HealthSample] = []
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
        savedSamples += makeSamples(event)
    }
    func verifyCurrent(_ event: ConsumptionEvent) async throws {
        guard !event.sampleIDs.isEmpty, event.sampleIDs.isSubset(of: Set((fixtureSamples + savedSamples).map(\.id))) else {
            throw HealthAccessError.entryChanged
        }
    }
    func replace(_ event: ConsumptionEvent, with replacement: ConsumptionDraft) async throws {
        if let saveError { throw saveError }
        try await delete(event)
        try await save(replacement)
    }
    func delete(_ event: ConsumptionEvent) async throws {
        try await verifyCurrent(event)
        saved.removeAll { "event:\($0.id.uuidString)" == event.id }
        savedSamples.removeAll { event.sampleIDs.contains($0.id) }
        fixtureSamples.removeAll { event.sampleIDs.contains($0.id) }
    }
    func samples(in range: DateInterval, limitedBy limits: [Nutrient: Date]) async throws -> [HealthSample] {
        if let queryError { throw queryError }
        return fixtureSamples + savedSamples
    }
    func limitedReadDates() async throws -> [Nutrient: Date] { readLimits }

    private func makeSamples(_ event: ConsumptionDraft) -> [HealthSample] {
        let total = event.nutrition
        let nutrients = total.loggableNutrients
        return nutrients.map { nutrient in
            HealthSample(id: UUID(), nutrient: nutrient, value: total[nutrient]!, date: event.date,
                         sourceName: "Tally", sourceBundle: ownBundleIdentifier, eventID: event.id.uuidString,
                         drinkName: event.name, brand: event.brand, size: event.size, isEstimated: total.estimated.contains(nutrient),
                         servingQuantity: event.quantity, servingAmount: event.servingAmount, perServingValue: event.perServingNutrition[nutrient],
                         expectedNutrients: Set(nutrients))
        }
    }
}
